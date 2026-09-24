<#
.SYNOPSIS
    Automated Idempotent Gentoo Linux WSL2 Installer & Configuration Script.

.DESCRIPTION
    This script automates the full lifecycle of setting up a Gentoo Linux WSL2 instance:
    1. Downloads the latest Stage3 OpenRC tarball from official Gentoo mirrors (if missing).
    2. Imports the rootfs into WSL2 (`C:\WSL\Gentoo`).
    3. Idempotently provisions Portage settings (`make.conf`), system locales, and core packages.
    4. Creates the target user account, configures passwordless sudo, and pre-creates `/nix`.
    5. Sets up a clean Python virtual environment (~/.venv/powerline) for Powerline.
    6. Imports Windows SSH keys and scans GitHub host keys cleanly.
    7. Prompts interactively for your SSH key passphrase to clone or update your dotfiles.
    8. Executes dotfile installation scripts (`install_dotfiles.sh all` / `install.sh`) inside
       the activated venv while intercepting pip calls to strip '--user' arguments dynamically.
    9. Configures `/etc/wsl.conf` and defaults login to the target user.

.NOTES
    Author: Markus Ellis
    Date: September 2026
    Idempotency: Safe to re-execute against an existing Gentoo WSL distribution.
#>

# ==============================================================================
# 1. Configuration Variables
# ==============================================================================
$DistroName   = "Gentoo"
$InstallDir   = "C:\WSL\Gentoo"
$TargetUser   = "memellis"
$DotfilesRepo = "git@github.com:memellis/dotfiles.git"

# Translate Windows SSH path directly to WSL /mnt/c format
$WinSshPath    = "$env:USERPROFILE\.ssh"
$WinSshPathWsl = "/mnt/c/" + ($WinSshPath -replace '^[A-Z]:\\', '' -replace '\\', '/')

Write-Host "=========================================================" -ForegroundColor Cyan
Write-Host "        Starting Gentoo WSL2 Automated Setup             " -ForegroundColor Cyan
Write-Host "=========================================================" -ForegroundColor Cyan
Write-Host " Notice: If prompted for an SSH passphrase during dotfiles" -ForegroundColor Yellow
Write-Host " clone/pull, enter it directly into this terminal.        " -ForegroundColor Yellow
Write-Host "---------------------------------------------------------" -ForegroundColor Cyan

# Ensure local storage directory exists
New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null

# Inspect registered WSL distros cleanly to check for existing instance
$RegisteredDistros = wsl --list --quiet 2>$null | ForEach-Object { $_.Trim() -replace "`0", "" }
$InstanceExists    = $RegisteredDistros -contains$DistroName

# ==============================================================================
# 2. Download & Import Stage3 (Only if Distro Does Not Exist)
# ==============================================================================
if (-not $InstanceExists) {
    Write-Host "Gentoo WSL instance not found. Performing fresh import..." -ForegroundColor Cyan
    Write-Host "Fetching latest Gentoo Stage3 download URL..." -ForegroundColor Cyan
    
    $BaseUrl   = "https://distfiles.gentoo.org/releases/amd64/autobuilds/"
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
    $OutFile     = Join-Path $InstallDir $TarballName

    Write-Host "Downloading $TarballName..." -ForegroundColor Cyan
    Invoke-WebRequest -Uri $DownloadUrl -OutFile $OutFile

    Write-Host "Importing $DistroName into WSL2..." -ForegroundColor Cyan
    wsl --import $DistroName $InstallDir $OutFile --version 2
    Remove-Item $OutFile -Force
} else {
    Write-Host "Existing $DistroName instance detected. Safe configuration update mode..." -ForegroundColor Yellow
}

# ==============================================================================
# 3. In-Distro Post-Install Bash Script Template
# ==============================================================================
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

echo "=== 4/8. Installing Core Packages (Sudo, Git, OpenSSH, Python) ==="
emerge --quiet --noreplace app-admin/sudo app-eselect/eselect-repository dev-vcs/git net-misc/openssh dev-lang/python

echo "=== 5/8. Managing Target User & System Directories ==="
if ! id "${USERNAME}" &>/dev/null; then
    useradd -m -G wheel,portage,users -s /bin/bash "${USERNAME}"
fi

# Configure passwordless sudo for wheel group
mkdir -p /etc/sudoers.d
echo "%wheel ALL=(ALL:ALL) NOPASSWD: ALL" > /etc/sudoers.d/wheel
chmod 0440 /etc/sudoers.d/wheel

# Pre-create /nix directory with user ownership
if [ ! -d /nix ]; then
    mkdir -m 0755 /nix
    chown "${USERNAME}" /nix
fi

USER_HOME="/home/${USERNAME}"

echo "=== 6/8. Provisioning Powerline Python Virtual Environment ==="
VENV_DIR="${USER_HOME}/.venv/powerline"
BIN_DIR="${USER_HOME}/.local/bin"

su - "${USERNAME}" -c "
    mkdir -p '${USER_HOME}/.venv' '${BIN_DIR}'
    if [ ! -d '${VENV_DIR}' ]; then
        python3 -m venv '${VENV_DIR}'
    fi
    '${VENV_DIR}/bin/pip' install --upgrade pip powerline-status
    ln -sf '${VENV_DIR}/bin/powerline' '${BIN_DIR}/powerline'
"

echo "=== 7/8. Importing Windows SSH Keys ==="
if [ -d "${WIN_SSH_DIR}" ]; then
    mkdir -p "${USER_HOME}/.ssh"
    cp -r "${WIN_SSH_DIR}"/* "${USER_HOME}/.ssh/" 2>/dev/null || true
    
    # Secure permissions for OpenSSH compliance
    chown -R "${USERNAME}:${USERNAME}" "${USER_HOME}/.ssh"
    chmod 700 "${USER_HOME}/.ssh"
    find "${USER_HOME}/.ssh" -type f -exec chmod 600 {} +
    find "${USER_HOME}/.ssh" -type f -name "*.pub" -exec chmod 644 {} +
    
    # Import GitHub host keys cleanly without duplicates
    su - "${USERNAME}" -c "ssh-keyscan -t rsa,ed25519 github.com > ${USER_HOME}/.ssh/known_hosts 2>/dev/null" || true
    chmod 600 "${USER_HOME}/.ssh/known_hosts" 2>/dev/null || true
    echo "SSH keys successfully imported to ${USER_HOME}/.ssh"
fi

echo "=== 8/8. Managing Dotfiles Repository ==="
DOTFILES_DIR="${USER_HOME}/dotfiles"

if [ -n "${DOTFILES_URL}" ]; then
    # Spawn interactive session as user to accept passphrase input
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

        # Source virtualenv and intercept pip to strip '--user' arguments dynamically
        source '${VENV_DIR}/bin/activate'
        
        pip() {
            local args=()
            for arg in \"\$@\"; do
                [[ \"\$arg\" == \"--user\" ]] || args+=(\"\$arg\")
            done
            command pip \"\${args[@]}\"
        }
        export -f pip

        if [ -f '${DOTFILES_DIR}/install_dotfiles.sh' ]; then
            echo 'Executing install_dotfiles.sh all...'
            bash '${DOTFILES_DIR}/install_dotfiles.sh' all
        elif [ -f '${DOTFILES_DIR}/install.sh' ]; then
            echo 'Executing install.sh...'
            bash '${DOTFILES_DIR}/install.sh'
        fi
        
        unset -f pip
        deactivate 2>/dev/null || true
        eval \$(ssh-agent -k) >/dev/null
    "
fi

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

# Substitute configuration variables into bash template
$BashScript = $BashScript.Replace("__TARGET_USER__", $TargetUser)
$BashScript = $BashScript.Replace("__DOTFILES_REPO__", $DotfilesRepo)
$BashScript = $BashScript.Replace("__WIN_SSH_DIR_WSL__", $WinSshPathWsl)

# ==============================================================================
# 4. Inject & Execute Post-Install Script in WSL
# ==============================================================================
$LocalScriptPath = Join-Path $InstallDir "post-install.sh"

# Convert Windows CRLF line endings to Linux LF before execution
[System.IO.File]::WriteAllText($LocalScriptPath, $BashScript.Replace("`r`n", "`n"))

Write-Host "Injecting and executing post-install script inside Gentoo..." -ForegroundColor Cyan

# Standard execution inherits console TTY streams directly for passphrase entry
wsl -d $DistroName -u root bash -c "tr -d '\r' < /mnt/c/WSL/Gentoo/post-install.sh > /root/setup.sh && chmod +x /root/setup.sh && /root/setup.sh"

Remove-Item $LocalScriptPath -ErrorAction SilentlyContinue

# ==============================================================================
# 5. Finalize Instance
# ==============================================================================
Write-Host "Restarting Gentoo instance as $TargetUser..." -ForegroundColor Green
wsl --shutdown
wsl -d $DistroName
