#!/usr/bin/env bash

#TODO
#- gtk-redshift
#- oh-my-zsh
#- i3-gaps
#- compton
#- variety
#- volti
#- clip by RB
#- python3-pip

set -euo pipefail
test ! -z ${DEBUG+x} && set -x

WORKDIR=$(realpath $(dirname $0))

cd ${WORKDIR}

# ==============================================================================

STAT_CMD=stat
DATE_CMD=date
ECHO_CMD=echo
BASE64_CMD=base64

log() {
    ${ECHO_CMD} -e "$(${DATE_CMD} --utc +%FT%T.%3NZ) $1"
}

log_info() {
    log " [INFO ] \e[92m$1\e[0m"
}

log_warn() {
    log " [WARN ] \e[93m$1\e[0m"
}

log_error() {
    log " [ERROR] \e[91m$1\e[0m"
}

# ==============================================================================
# base system
# ==============================================================================

self_update() {
    log_info "Checking for self updates..."
    if [[ ! -d .git ]]; then
        log_error "YO! where is your git repo ?"
        exit 1
    fi
    if [[ -n $(which git) ]]; then
        if [[ -z "$(git diff)" ]]; then
            git fetch origin
            if [[ "$(git log HEAD..origin/master --oneline)" != "" ]]; then
                log_info "Self updating..."
                git merge origin/master
                log_info "Self update done. Run $0 again."
                exit 0
            fi
            log_info "Up to date."
        else
            log_warn "Local changes detected, skipping self-update."
        fi
    else
        # skip if sys was just copied over to the new machine
        log_warn "Git not installed, skipping self-update."
    fi
}

check_root_password() {
    if os_linux; then
        log_info "Checking root password..."
        if [[ "$(sudo passwd -S root | awk '{print $2}')" == "P" ]]; then
            log_info "Root password is enabled, locking now..."
            sudo passwd -l root
        fi
        log_info "Root password is locked."
    fi
}

check_reboot_required() {
    if os_ubuntu; then
        if [[ -f /var/run/reboot-required ]]; then
            log_info "
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!!!                                                 !!!
!!!        /var/run/reboot-required says            !!!
!!!        *** System restart required ***          !!!
!!!                                                 !!!
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
            read -n 1 -p "Press any key to continue or Ctrl+C to exit."
        fi
    fi
}

apt_update_all() {
    log_info "Checking for APT packages updates..."
    sudo apt update
    sudo apt dist-upgrade -y
    sudo apt autoremove -y
    log_info "APT packages up to date."
}

apt_install_package() {
    PACKAGE=$1
    sudo apt install ${PACKAGE} -y
}

apt_package_installed() {
    PACKAGE=$1
    dpkg -s ${PACKAGE} &>/dev/null && return 0 || return 1
}

check_install_apt_package() {
    PACKAGE=$1
    LABEL=${2:-$1}
    log_info "Checking ${LABEL}..."
    if ! apt_package_installed ${PACKAGE}; then
        log_info "Installing ${LABEL}..."
        apt_install_package ${PACKAGE}
    fi
    log_info "${LABEL} is installed."
}

check_install_download_deb() {
    PACKAGE=$1
    LABEL=$2
    URL=$3
    LOCAL_FILE=$4
    log_info "Checking ${LABEL}..."
    if ! apt_package_installed ${PACKAGE}; then
        log_info "Installing ${LABEL}..."
        wget -c ${URL} -O ${LOCAL_FILE}
        sudo apt install -y ${LOCAL_FILE}
        rm -f ${LOCAL_FILE}
    fi
    log_info "${LABEL} is installed."
}

snap_update_all() {
    log_info "Checking for snap packages updates..."
    sudo snap refresh
    log_info "snap packages up to date."
}

snap_install_package() {
    PACKAGE=$1
    OPTS=${2:-}
    sudo snap install ${PACKAGE} ${OPTS}
}

snap_package_installed() {
    PACKAGE=$1
    INSTALLED=$(sudo snap list | grep "^${PACKAGE} " 2>/dev/null)
    test -n "${INSTALLED}" && return 0 || return 1
}

check_install_snap_package() {
    PACKAGE=$1
    LABEL=${2:-$1}
    OPTS=${3:-}
    log_info "Checking ${LABEL}..."
    if ! snap_package_installed ${PACKAGE}; then
        log_info "Installing ${LABEL}..."
        snap_install_package ${PACKAGE} ${OPTS}
    fi
    log_info "${LABEL} is installed."
}

install_coreutils() {
    check_install_apt_package curl "cURL"
    check_install_apt_package gtk-redshift "GTK RedShift"
}

install_ssh() {
    check_install_apt_package openssh-client "SSH Client"
    check_install_apt_package openssh-server "SSH Server"
    check_install_apt_package autossh "auto SSH"
}

install_rsync() {
    check_install_apt_package rsync Rsync
}

install_git() {
    check_install_apt_package git Git
    check_install_apt_package gitk GitK
}

# ==============================================================================
# personal config
# ==============================================================================

check_permissions() {
    MOD=$1
    FILE=$2
    if [[ "$(${STAT_CMD} -c %a ${FILE})" != "${MOD}" ]]; then
        chmod "${MOD}" "${FILE}"
    fi
}

install_file() {
    SOURCE=$1
    DESTINATION=$2
    MOD=$3
    if [[ ! -f ${DESTINATION} ]]; then
        if [[ ${SOURCE} == *.gpg ]] && [[ ${DESTINATION} != *.gpg ]]; then
            gpg_decrypt_file ${SOURCE} ${DESTINATION}
        elif [[ ${SOURCE} != *.gpg ]] && [[ ${DESTINATION} == *.gpg ]]; then
            gpg_encrypt_file ${SOURCE} ${DESTINATION}
        else
            cp -f ${SOURCE} ${DESTINATION}
        fi
    fi
    check_permissions ${MOD} ${DESTINATION}
}

check_ssh_id() {
    SERVER=$1
    ssh -o PasswordAuthentication=no ${SERVER} exit &>/dev/null || ssh-copy-id ${SERVER}
}

add_line() {
    FILE=$1
    LINE=$2
    grep -q -F "${LINE}" "${FILE}" || echo "${LINE}" >>"${FILE}"
}

sudo_add_line() {
    FILE=$1
    LINE=$2
    sudo grep -q -F "${LINE}" "${FILE}" || echo "${LINE}" | sudo tee -a "${FILE}"
}

install_zsh() {
    log_info "Installing zsh..."
    check_install_apt_package zsh Zsh
    log_info "Zsh installed."
}

configure_zsh() {
        # test!
    log_info "Configuring zsh..."
    sudo sed -i 's/\/home\/alguevara:\/bin\/bash/\/home\/alguevara:\/usr\/bin\/zsh/g' /etc/passwd
    log_info "Zsh configured."
}

configure_git() {
    log_info "Configuring git..."
    git config --global user.name "Alexei Guevara"
    git config --global user.email alguevara@ebay.com
    git config --global branch.autosetuprebase always
    git config --global pull.rebase true
    git config --global core.editor vim
    git config --global color.ui true
    git config --global push.default simple
    log_info "git configured."
}

install_i3() {
    check_install_apt_package i3 i3
}

install_ubuntu_restricted_extras() {
    check_install_apt_package ubuntu-restricted-extras "Ubuntu Restricted Extras"
}

# ==============================================================================
# system/desktop tools
# ==============================================================================

install_chromium() {
    check_install_apt_package chromium-browser Chromium
}

# ==============================================================================
# dev packages
# ==============================================================================

install_docker() {
    log_info "Checking Docker..."
    if ! apt_package_installed docker-ce; then
        log_info "Installing Docker..."
        sudo apt install -y apt-transport-https ca-certificates curl software-properties-common
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
        # sudo add-apt-repository -y "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
        # sudo add-apt-repository -y "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) edge"
        # sudo add-apt-repository -y "deb [arch=amd64] https://download.docker.com/linux/ubuntu bionic stable"
        sudo add-apt-repository -y "deb [arch=amd64] https://download.docker.com/linux/ubuntu bionic edge"
        sudo apt update
        apt_install_package docker-ce
        if [[ -z "$(grep docker /etc/group)" ]]; then
            sudo groupadd docker
        fi
        sudo usermod -aG docker ${USER}
        sudo systemctl enable docker
    fi
    log_info "Docker is installed."
}

install_docker_compose() {
    log_info "Checking Docker Compose..."
    if [[ -z "$(which docker-compose)" ]]; then
        log_info "Installing Docker Compose..."
    sudo curl -L "https://github.com/docker/compose/releases/download/1.22.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose
    fi
    log_info "Docker Compose is installed."
}

install_cli_utils() {
    check_install_apt_package tmux tmux
    check_install_apt_package jq jq
    check_install_apt_package httpie HTTPie
}

install_ag() {
    check_install_apt_package silversearcher-ag "Silver Searcher"
}

install_conky() {
    check_install_apt_package conky "Conky"
}

install_vim() {
    check_install_apt_package vim "Vim"
}

configure_xrandr() {
    log_info "Configuring xrandr..."
    log_info "Xrandr configured."
}

clone_repo() {
    URL=$1
    DESTINATION=$2
    PARENT_DIR=$(dirname ${DESTINATION})
    if [[ ! -d ${PARENT_DIR} ]]; then
        mkdir -p ${PARENT_DIR}
    fi
    if [[ ! -d ${DESTINATION} ]]; then
        git clone $URL $DESTINATION
    fi
}

install_nvidia_driver() {
    log_info "Installing NVidia Driver..."

    sudo add-apt-repository -y "ppa:graphics-drivers/ppa"
    sudo apt-get -y update
    sudo apt-get install -y nvidia-driver-390
    sudo apt-get install -y nvidia-settings

    log_info "NVidia Driver installed."
}

install_latest_intel_driver() {
    log_info "Installing Latest Intel Video Driver..."

    sudo add-apt-repository -y "ppa:oibaf/graphics-drivers"
    sudo apt-get install -y --reinstall xserver-xorg-video-intel
    log_info "Latest Intel Video Driver installed."
}

install_nvidia_docker() {
    if apt_package_installed nvidia-docker; then
       log_info "NVidia Docker is installed already."
       return
    fi

    log_info "Installing NVidia Docker..."
    curl -s -L https://nvidia.github.io/nvidia-docker/gpgkey | \
        sudo apt-key add -
    distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
    curl -s -L https://nvidia.github.io/nvidia-docker/$distribution/nvidia-docker.list | \
        sudo tee /etc/apt/sources.list.d/nvidia-docker.list
    sudo apt-get -y update
    check_install_apt_package nvidia-docker2 "NVidia Docker v2"
    sudo pkill -SIGHUP dockerd
    log_info "NVidia Docker Installed."
}


disabled_wakeup_from_kb_mouse() {
    sudo cp files/rc.local /etc/
    sudo chmod +x /etc/rc.local
}

suspend_on_power_button_press() {
    sudo_add_line /etc/systemd/logind.conf "HandlePowerKey=suspend"
}

# ==============================================================================

install() {

    # base system
    self_update
    apt_update_all
    snap_update_all
    check_reboot_required
    check_root_password
    install_coreutils
    install_ssh
    install_rsync
    install_git

    # hardware setup
    disabled_wakeup_from_kb_mouse
    suspend_on_power_button_press

    # personal config
    install_zsh
    configure_zsh
    install_i3
    install_vim
    #configure_xrandr
    install_ubuntu_restricted_extras

    # system/desktop tools
    install_chromium
    install_conky

    # dev packages
    install_docker
    install_docker_compose
    install_cli_utils
    install_ag

    # le ML setup
    install_nvidia_driver
    install_nvidia_docker

    # le usb display
    install_latest_intel_driver

    log_info "Great Success!"
    log_info "Re-start to make sure it's all good :)"

}

main() {

    OPERATION=$1

    case ${OPERATION} in
        install)
            install
            ;;
        *)
            echo "
Usage:
    ./sys.sh install         check/install everything
"
            exit 1
            ;;
    esac

}

if [ "${EUID}" == "0" ]; then
    echo "Naughty naughty!"
    exit 1
fi

main ${1:-}
