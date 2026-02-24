#!/bin/bash
set -e

# Check if HOST_UID/HOST_GID are explicitly set (via .env or environment)
if [ -z "$HOST_UID" ] || [ -z "$HOST_GID" ]; then
    echo "============================================"
    echo " WARNING: HOST_UID/HOST_GID not set!"
    echo ""
    echo " Copy .env.example to .env and set your IDs:"
    echo "   cp .env.example .env"
    echo ""
    echo " Check your IDs with: id -u && id -g"
    echo " Falling back to UID/GID 1000."
    echo "============================================"
fi

HOST_UID="${HOST_UID:-1000}"
HOST_GID="${HOST_GID:-1000}"
USERNAME="dev"

# Remove existing user/group that conflicts with host IDs
EXISTING_USER=$(getent passwd "$HOST_UID" 2>/dev/null | cut -d: -f1 || true)
if [ -n "$EXISTING_USER" ] && [ "$EXISTING_USER" != "$USERNAME" ]; then
    userdel "$EXISTING_USER" 2>/dev/null || true
fi

EXISTING_GROUP=$(getent group "$HOST_GID" 2>/dev/null | cut -d: -f1 || true)
if [ -n "$EXISTING_GROUP" ] && [ "$EXISTING_GROUP" != "$USERNAME" ]; then
    groupmod -n "$USERNAME" "$EXISTING_GROUP"
fi

# Create group/user matching host IDs
if ! getent group "$HOST_GID" > /dev/null 2>&1; then
    groupadd -g "$HOST_GID" "$USERNAME"
fi

if ! id "$USERNAME" > /dev/null 2>&1; then
    useradd -m -u "$HOST_UID" -g "$HOST_GID" -s /bin/bash "$USERNAME"
fi

# Allow passwordless sudo
echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/"$USERNAME"

# SSH server setup
mkdir -p /run/sshd
# Generate host keys if missing
[ ! -f /etc/ssh/ssh_host_rsa_key ] && ssh-keygen -A
# Allow password auth for dev user (set empty password)
passwd -d "$USERNAME" 2>/dev/null || true
sed -i 's/^#\?PermitEmptyPasswords.*/PermitEmptyPasswords yes/' /etc/ssh/sshd_config
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
# Copy host authorized_keys if mounted
if [ -f /workspace/.ssh/authorized_keys ]; then
    HOME_DIR=$(eval echo "~$USERNAME")
    mkdir -p "$HOME_DIR/.ssh"
    command cp /workspace/.ssh/authorized_keys "$HOME_DIR/.ssh/authorized_keys"
    chown -R "$HOST_UID:$HOST_GID" "$HOME_DIR/.ssh"
    chmod 700 "$HOME_DIR/.ssh"
    chmod 600 "$HOME_DIR/.ssh/authorized_keys"
fi
# Start SSH daemon in background
/usr/sbin/sshd

exec gosu "$USERNAME" "$@"
