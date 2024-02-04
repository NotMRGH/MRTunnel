#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
blue='\033[0;34m'
purple='\033[0;35m'
cyan='\033[0;36m'
white='\033[0;37m'
rest='\033[0m'
myip=$(hostname -I | awk '{print $1}')

root_access() {
    if [ "$EUID" -ne 0 ]; then
        echo "This script requires root access. please run as root."
        exit 1
    fi
}

check_dependencies() {
    detect_distribution

    local dependencies=("wget" "lsof" "iptables" "unzip" "gcc" "git" "curl" "tar")
    
    for dep in "${dependencies[@]}"; do
        if ! command -v "${dep}" &> /dev/null; then
            echo "${dep} is not installed. Installing..."
            sudo "${package_manager}" install "${dep}" -y
        fi
    done
}

install_rtt() {
    root_access

    apt-get update -y

    REQUIRED_PKG="unzip"
    PKG_OK=$(dpkg-query -W --showformat='${Status}\n' $REQUIRED_PKG|grep "install ok installed")
    echo Checking for $REQUIRED_PKG: $PKG_OK
    if [ "" = "$PKG_OK" ]; then
    echo "Setting up $REQUIRED_PKG."
    sudo apt-get --yes install $REQUIRED_PKG
    fi

    REQUIRED_PKG="wget"
    PKG_OK=$(dpkg-query -W --showformat='${Status}\n' $REQUIRED_PKG|grep "install ok installed")
    echo Checking for $REQUIRED_PKG: $PKG_OK
    if [ "" = "$PKG_OK" ]; then
    echo "Setting up $REQUIRED_PKG."
    sudo apt-get --yes install $REQUIRED_PKG
    fi

    REQUIRED_PKG="lsof" 
    PKG_OK=$(dpkg-query -W --showformat='${Status}\n' $REQUIRED_PKG|grep "install ok installed")
    echo Checking for $REQUIRED_PKG: $PKG_OK
    if [ "" = "$PKG_OK" ]; then
    echo "Setting up $REQUIRED_PKG."
    sudo apt-get --yes install $REQUIRED_PKG
    fi

    printf  "\n"
    printf  "\n"

    echo "downloading ReverseTlsTunnel"

    printf  "\n"


    case $(uname -m) in
        x86_64)  URL="https://github.com/NotMRGH/ReverseTlsTunnel/releases/latest/download/linux_amd64.zip" ;;
        arm)     URL="https://github.com/NotMRGH/ReverseTlsTunnel/releases/latest/download/linux_arm64.zip" ;;
        aarch64) URL="https://github.com/NotMRGH/ReverseTlsTunnel/releases/latest/download/linux_arm64.zip" ;;
    
        *)   echo "Unable to determine system architecture."; exit 1 ;;

    esac

    wget  $URL -O linux_amd64.zip
    unzip -o linux_amd64.zip
    chmod +x RTT
    rm linux_amd64.zip

    echo "finished."

    printf  "\n"
}


install() {
    root_access
    check_dependencies
    install_rtt
    cd /etc/systemd/system

    read -p "Which server do you want to use? (Enter '1' for Iran(internal-server) or '2' for Kharej(external-server) or '3' custom RTT ) : " server_choice
    if [ "$server_choice" == "2" ]; then
        read -p "Please Enter IP(IRAN) : " server_ip
        
        if [ -f "/etc/systemd/system/Tunnel_$server_ip.service" ]; then
            echo "This Tunnel is already installed."
            exit 1
        fi

        read -p "Please Enter SNI (default : sheypoor.com): " sni
        sni=${sni:-sheypoor.com}
        read -p "Please Enter Password (Please choose the same password on both servers): " password

        read -p "Please Enter Port(for connection between IRAN and Kharej) : " server_port
        arguments="--kharej --iran-ip:$server_ip --iran-port:$server_port --toip:127.0.0.1 --toport:multiport --password:$password --sni:$sni --keep-ufw --mux-width:2 --terminate:24"
    elif [ "$server_choice" == "1" ]; then
        read -p "Please Enter IP(Kharej) : " server_ip

        if [ -f "/etc/systemd/system/Tunnel_$server_ip.service" ]; then
            echo "This Tunnel is already installed."
            exit 1
        fi

        read -p "Please Enter SNI (default : sheypoor.com): " sni
        sni=${sni:-sheypoor.com}
        read -p "Please Enter Password (Please choose the same password on both servers): " password

        arguments="--iran --lport:23-65535 --sni:$sni --password:$password --keep-ufw --mux-width:2 --terminate:24"
    elif [ "$server_choice" == "3" ]; then

        read -p "Please Enter IP(Kharej or IRAN) : " server_ip

        if [ -f "/etc/systemd/system/Tunnel_$server_ip.service" ]; then
            echo "This Tunnel is already installed."
            exit 1
        fi

        read -p "Enter RTT arguments (Example: --iran --lport:443 --sni:splus.ir --password:123): " arguments
    else
        echo "Invalid choice. Please enter '1' or '2' or '3'."
        exit 1
    fi

    cat <<EOL > Tunnel_$server_ip.service
[Unit]
Description=Tunnel_$server_ip

[Service]
Type=idle
User=root
WorkingDirectory=/root
ExecStart=/root/RTT $arguments
Restart=always

[Install]
WantedBy=multi-user.target
EOL

    sudo systemctl daemon-reload
    sudo systemctl start Tunnel_$server_ip.service
    sudo systemctl enable Tunnel_$server_ip.service
    echo "This Tunnel with name (Tunnel_$server_ip) was successfully installed"
}


uninstall() {
    read -p "Please Enter IP(Kharej or IRAN) : " server_ip
    if [ ! -f "/etc/systemd/system/Tunnel_$server_ip.service" ]; then
        echo "This Tunnel is not installed."
        return
    fi

    sudo systemctl stop Tunnel_$server_ip.service
    sudo systemctl disable Tunnel_$server_ip.service

    sudo rm /etc/systemd/system/Tunnel_$server_ip.service
    sudo systemctl reset-failed
    sudo rm RTT
    sudo rm install.sh 2>/dev/null

    echo "Uninstallation completed successfully."
}

start_tunnel() {
    read -p "Please Enter IP(Kharej or IRAN) : " server_ip

    if sudo systemctl is-enabled --quiet Tunnel_$server_ip.service; then
        sudo systemctl start Tunnel_$server_ip.service > /dev/null 2>&1

        if sudo systemctl is-active --quiet Tunnel_$server_ip.service; then
            echo "Tunnel service started."
        else
            echo "Tunnel service failed to start."
        fi
    else
        echo "Tunnel is not installed."
    fi
}

stop_tunnel() {
    read -p "Please Enter IP(Kharej or IRAN) : " server_ip

    if sudo systemctl is-enabled --quiet Tunnel_$server_ip.service; then
        sudo systemctl stop Tunnel_$server_ip.service > /dev/null 2>&1

        if sudo systemctl is-active --quiet Tunnel_$server_ip.service; then
            echo "Tunnel service failed to stop."
        else
            echo "Tunnel service stopped."
        fi
    else
        echo "Tunnel is not installed."
    fi
}

check_tunnel_status() {
    read -p "Please Enter IP(Kharej or IRAN) : " server_ip

    if sudo systemctl is-active --quiet Tunnel_$server_ip.service; then
        echo -e "${yellow}Tunnel is: ${green}[running ✔]${rest}"
    else
        echo -e "${yellow}Tunnel is:${red}[Not running ✗ ]${rest}"
    fi
}

# Main menu
clear
echo -e "${cyan}By --> NotMR_GH * Github.com/NotMRGH * ${rest}"
echo -e "Your IP is: ${cyan}($myip)${rest} "
echo -e "${yellow}******************************${rest}"
echo -e " ${purple}--------#- Reverse Tls Tunnel -#--------${rest}"
echo -e "${green}1) Install${rest}"
echo -e "${red}2) Uninstall${rest}"
echo "3) Start"
echo "4) Stop"
echo "5) Check Status"
echo "0) Exit"
read -p "Please choose: " choice

case $choice in
    1)
        install
        ;;
    2)
        uninstall
        ;;
    3)
        start_tunnel
        ;;
    4)
        stop_tunnel
        ;;
    5)
        check_tunnel_status
        ;;
    0)   
        exit
        ;;
    *)
        echo "Invalid choice. Please try again."
       ;;
esac
