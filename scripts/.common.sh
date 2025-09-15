INFO='\033[1;36m'  # Cyan (info color)
ERROR='\033[1;31m' # Red (error color)
RESET='\033[0m'     # Reset to default color

# Function to print messages in color
info() {
    echo -e "[*] ${INFO}$1${RESET}"
}
error() {
    echo -e "[-] ${ERROR}$1${RESET}"
}
