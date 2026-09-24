# ==============================================================================
# Gentoo WSL2 Automated Installer & Post-Configuration Script (Idempotent)
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. Configuration Variables
# ------------------------------------------------------------------------------
$DistroName   = "Gentoo"
$InstallDir   = "C:\WSL\Gentoo"
$TargetUser   = "memellis"
$DotfilesRepo = "git@github.com:memellis/dotfiles.git"

# Translate Windows SSH path directly to WSL /mnt/c format
$WinSshPath = "$env:USERPROFILE\.ssh"
$WinSshPathWsl = "/mnt/c/" + ($WinSshPath -replace '^[A-Z]:\\', '' -replace '\\', '/')

New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null

# Check if distro already exists in WSL
$RegisteredDistros = wsl --list --quiet 2>$null | ForEach-Object { $_.Trim() -replace "`0", "" }
$InstanceExists = $RegisteredDistros -contains$DistroName

# ------------------------------------------------------------------------------
# 2. Download & Import (Only if Distro Does Not Exist)
# ------------------------------------------------------------------------------
if (-not $InstanceExists) {
    Write-Host "Gentoo WSL instance not found. Performing fresh import..." -ForegroundColor Cyan
    Write-Host "Fetching latest Gentoo Stage3 download URL..." -ForegroundColor Cyan
    $BaseUrl = "https://distfiles.gentoo.org/releases/amd64/autobuilds/"
    $LatestTxt = Invoke-RestMethod -Uri "$($BaseUrl)latest-stage3-amd64-openrc.txt"

    # Parse relative path while stripping PGP signature headers
    $RelativePath = ($LatestTxt -split "`n" | Where-Object { 
        $_ -and -not $_.StartsWith("#") -and -not $_.StartsWith("-----") -and $_.Contains("stage3") 
    } | Select-Object -First 1) -split "\s+" | Select-Object -First 1

    if (-not $RelativePath) {
        Write-Error "Failed to parse Stage3 download path from Gentoo mirrors."
        exit 1
    }

    $DownloadUrl = "$BaseUrl$RelativePath"
    $TarballName = Split-Path $DownloadUrl -Leaf
    $OutFile = Join-Path $InstallDir $TarballName

    Write-Host "Downloading $TarballName..." -ForegroundColor Cyan
    Invoke-WebRequest -Uri $DownloadUrl -OutFile $OutFile

    Write-Host "Importing $DistroName into WSL2..." -ForegroundColor Cyan
    wsl --import $DistroName $InstallDir $OutFile --version 2
    Remove-Item $OutFile -Force
} else {
    Write-Host "Existing $DistroName instance detected. Safe configuration update mode..." -ForegroundColor Yellow
}

# ------------------------------------------------------------------------------
# 3. In-Distro Post-Install Bash Script
# ------------------------------------------------------------------------------
$BashScript = @'
#!/bin/bash
set -e

USERNAME="__TARGET_USER__"
DOTFILES_URL="__DOTFILES_REPO__"
WIN_SSH_DIR="__WIN_SSH_DIR_WSL__"
CPU_CORES=$(nproc)

echo "=== 1/8. Configuring Portage (/etc/portage/make.conf) ==="
cat <<EOF > /etc/portage/make.conf
COMMON_FLAGS="-O2 -pipe -march=native"
CFLAGS="${COMMON_FLAGS}"
CXXFLAGS="${COMMON_FLAGS}"
FCFLAGS="${COMMON_FLAGS}"
FFLAGS="${COMMON_FLAGS}"
MAKEOPTS="-j${CPU_CORES}"
ACCEPT_LICENSE="*"
FEATURES="binpkg-logs parallel-fetch"
LC_MESSAGES=C.utf8
EOF

echo "=== 2/8. Syncing Portage Tree ==="
mkdir -p /var/db/repos/gentoo
if [ ! -f /var/db/repos/gentoo/profiles/repo_name ]; then
    emerge-webrsync
fi

echo "=== 3/8. Configuring Locales ==="
cat <<EOF > /etc/locale.gen
en_US.UTF-8 UTF-8
en_GB.UTF-8 UTF-8
EOF
locale-gen

if eselect locale list | grep -q "en_US.utf8"; then
    eselect locale set en_US.utf8
elif eselect locale list | grep -q "en_GB.utf8"; then
    eselect locale set en_GB.utf8
fi
env-update && source /etc/profile

echo "=== 4/8. Installing Core Packages (Sudo, Git, OpenSSH, Pip) ==="
emerge --quiet --noreplace app-admin/sudo app-eselect/eselect-repository dev-vcs/git net-misc/openssh dev-python/pip

echo "=== 5/8. Managing Target User: '${USERNAME}' ==="
if ! id "${USERNAME}" &>/dev/null; then
    useradd -m -G wheel,portage,users -s /bin/bash "${USERNAME}"
fi

mkdir -p /etc/sudoers.d
echo "%wheel ALL=(ALL:ALL) ALL" > /etc/sudoers.d/wheel
chmod 0440 /etc/sudoers.d/wheel

echo "=== 6/8. Importing Windows SSH Keys ==="
USER_HOME="/home/${USERNAME}"

if [ -d "${WIN_SSH_DIR}" ]; then
    mkdir -p "${USER_HOME}/.ssh"
    cp -r "${WIN_SSH_DIR}"/* "${USER_HOME}/.ssh/" 2>/dev/null || true
    
    chown -R "${USERNAME}:${USERNAME}" "${USER_HOME}/.ssh"
    chmod 700 "${USER_HOME}/.ssh"
    find "${USER_HOME}/.ssh" -type f -exec chmod 600 {} +
    find "${USER_HOME}/.ssh" -type f -name "*.pub" -exec chmod 644 {} +
    
    su - "${USERNAME}" -c "ssh-keyscan -t rsa,ed25519 github.com > ${USER_HOME}/.ssh/known_hosts 2>/dev/null" || true
    chmod 600 "${USER_HOME}/.ssh/known_hosts" 2>/dev/null || true
    echo "SSH keys successfully imported to ${USER_HOME}/.ssh"
fi

echo "=== 7/8. Managing Dotfiles Repository ==="
DOTFILES_DIR="${USER_HOME}/dotfiles"

if [ -n "${DOTFILES_URL}" ]; then
    su - "${USERNAME}" -c "
        eval \$(ssh-agent -s) >/dev/null
        
        echo ''
        echo '---------------------------------------------------------'
        echo '  SSH Passphrase Required for Git Authentication'
        echo '---------------------------------------------------------'
        
        if [ -f '${USER_HOME}/.ssh/id_ed25519' ]; then
            ssh-add '${USER_HOME}/.ssh/id_ed25519'
        elif [ -f '${USER_HOME}/.ssh/id_rsa' ]; then
            ssh-add '${USER_HOME}/.ssh/id_rsa'
        else
            ssh-add
        fi

        if [ ! -d '${DOTFILES_DIR}' ]; then
            echo 'Cloning ${DOTFILES_URL} into ${DOTFILES_DIR}...'
            GIT_SSH_COMMAND='ssh -o StrictHostKeyChecking=accept-new' git clone '${DOTFILES_URL}' '${DOTFILES_DIR}'
        else
            echo 'Updating existing dotfiles repository...'
            cd '${DOTFILES_DIR}'
            GIT_SSH_COMMAND='ssh -o StrictHostKeyChecking=accept-new' git pull
        fi

        if [ -d '${DOTFILES_DIR}' ]; then
            cd '${DOTFILES_DIR}'
            
            if [ -f 'install_dotfiles.sh' ]; then
                echo 'Executing install_dotfiles.sh all...'
                bash install_dotfiles.sh all
            elif [ -f 'install.sh' ]; then
                echo 'Executing install.sh all...'
                bash install.sh all
            fi
        fi
        
        eval \$(ssh-agent -k) >/dev/null
    "
fi

echo "=== 8/8. Configuring /etc/wsl.conf ==="
cat <<EOF > /etc/wsl.conf
[user]
default=${USERNAME}

[boot]
systemd=false

[interop]
enabled=true
appendWindowsPath=true
EOF

echo "=== Gentoo WSL2 Setup Complete! ==="
'@

# Substitute variables into template
$BashScript = $BashScript.Replace("__TARGET_USER__", $TargetUser)
$BashScript = $BashScript.Replace("__DOTFILES_REPO__", $DotfilesRepo)
$BashScript = $BashScript.Replace("__WIN_SSH_DIR_WSL__", $WinSshPathWsl)

# ------------------------------------------------------------------------------
# 4. Inject & Execute Post-Install Script in WSL
# ------------------------------------------------------------------------------
$LocalScriptPath = Join-Path $InstallDir "post-install.sh"
[System.IO.File]::WriteAllText($LocalScriptPath, $BashScript.Replace("`r`n", "`n"))

Write-Host "Injecting and executing post-install script inside Gentoo..." -ForegroundColor Cyan

wsl -d $DistroName -u root bash -c "tr -d '\r' < /mnt/c/WSL/Gentoo/post-install.sh > /root/setup.sh && chmod +x /root/setup.sh && /root/setup.sh"

Remove-Item $LocalScriptPath -ErrorAction SilentlyContinue

# ------------------------------------------------------------------------------
# 5. Finalize Instance
# ------------------------------------------------------------------------------
Write-Host "Restarting Gentoo instance as $TargetUser..." -ForegroundColor Green
wsl --shutdown
wsl -d $DistroName
