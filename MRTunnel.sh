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

if [ "$EUID" -ne 0 ]; then
    echo "This script requires root access. please run as root."
    exit 1
fi

if [[ -f /etc/os-release ]]; then
    source /etc/os-release
    release=$ID
elif [[ -f /usr/lib/os-release ]]; then
    source /usr/lib/os-release
    release=$ID
else
    echo "Failed to check the system OS, please contact the author!" >&2
    exit 1
fi

enable_bbr() {

    echo -e "${green}instaling BBR${plain}"

    if grep -q "net.core.default_qdisc=fq" /etc/sysctl.conf && grep -q "net.ipv4.tcp_congestion_control=bbr" /etc/sysctl.conf; then
        exit 0
    fi

    case "${release}" in
    ubuntu | debian | armbian)
        apt-get update && apt-get install -yqq --no-install-recommends ca-certificates
        ;;
    centos | almalinux | rocky | oracle)
        yum -y update && yum -y install ca-certificates
        ;;
    fedora)
        dnf -y update && dnf -y install ca-certificates
        ;;
    arch | manjaro | parch)
        pacman -Sy --noconfirm ca-certificates
        ;;
    *)
        echo -e "${red}Unsupported operating system. Please check the script and install the necessary packages manually.${plain}\n"
        exit 1
        ;;
    esac

    echo "net.core.default_qdisc=fq" | tee -a /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control=bbr" | tee -a /etc/sysctl.conf

    sysctl -p

    if [[ $(sysctl net.ipv4.tcp_congestion_control | awk '{print $3}') == "bbr" ]]; then
        echo -e "${green}BBR has been enabled successfully.${plain}"
    else
        echo -e "${red}Failed to enable BBR. Please check your system configuration.${plain}"
    fi
}

check_dependencies_reverse() {

    local dependencies=("wget" "lsof" "iptables" "unzip" "gcc" "git" "curl" "tar")

    for dep in "${dependencies[@]}"; do
        if ! command -v "${dep}" &>/dev/null; then
            echo "${dep} is not installed. Installing..."
            sudo "${package_manager}" install "${dep}" -y
        fi
    done
}

install_rtt() {

    REQUIRED_PKG="unzip"
    PKG_OK=$(dpkg-query -W --showformat='${Status}\n' $REQUIRED_PKG | grep "install ok installed")
    echo Checking for $REQUIRED_PKG: $PKG_OK
    if [ "" = "$PKG_OK" ]; then
        echo "Setting up $REQUIRED_PKG."
        sudo apt-get --yes install $REQUIRED_PKG
    fi

    REQUIRED_PKG="wget"
    PKG_OK=$(dpkg-query -W --showformat='${Status}\n' $REQUIRED_PKG | grep "install ok installed")
    echo Checking for $REQUIRED_PKG: $PKG_OK
    if [ "" = "$PKG_OK" ]; then
        echo "Setting up $REQUIRED_PKG."
        sudo apt-get --yes install $REQUIRED_PKG
    fi

    REQUIRED_PKG="lsof"
    PKG_OK=$(dpkg-query -W --showformat='${Status}\n' $REQUIRED_PKG | grep "install ok installed")
    echo Checking for $REQUIRED_PKG: $PKG_OK
    if [ "" = "$PKG_OK" ]; then
        echo "Setting up $REQUIRED_PKG."
        sudo apt-get --yes install $REQUIRED_PKG
    fi

    printf "\n"
    printf "\n"

    echo "downloading ReverseTlsTunnel"

    printf "\n"

    case $(uname -m) in
    x86_64) URL="https://github.com/NotMRGH/MRTunnel/releases/latest/download/linux_Reverse_amd64.zip" ;;
    arm) URL="https://github.com/NotMRGH/MRTunnel/releases/latest/download/linux_Reverse_arm64.zip" ;;
    aarch64) URL="https://github.com/NotMRGH/MRTunnel/releases/latest/download/linux_Reverse_arm64.zip" ;;

    *)
        echo "Unable to determine system architecture."
        exit 1
        ;;

    esac

    wget $URL -O linux_amd64.zip
    unzip -o linux_amd64.zip
    chmod +x RTT
    rm linux_amd64.zip

    echo "finished."

    printf "\n"
}

install_reverse() {
    check_dependencies_reverse
    install_rtt
    enable_bbr

    files=$(ls -1A /etc/systemd/system/Tunnel-reverse-* 2>/dev/null)

    if [ ! -z "$files" ]; then
        echo -e "${green}Tunnel is already installed! (Use add tunnel)${plain}"
        exit 1
    fi

    add_reverse
}

add_reverse() {

    files=$(ls -1A /etc/systemd/system/Tunnel-reverse-* 2>/dev/null)

    if [ ! -z "$files" ]; then
        for file in $files; do
            port=$(echo $file | cut -d'-' -f4 | sed 's/\.service//')

            if [ "$port" = "multi_port" ]; then
                echo "Multi-Port are installed before use add tunnel uninstall multi-port."
                exit 1
            fi
        done
    fi

    cd /etc/systemd/system

    read -p "Which server do you want to use? (Enter '1' for Iran(internal-server) or '2' for Kharej(external-server): " server_choice
    if [ "$server_choice" == "2" ]; then

        read -p "Please Enter SNI (default : sheypoor.com): " sni
        sni=${sni:-sheypoor.com}

        read -p "Please Enter Password (Please choose the same password on both servers): " password

        read -p "Which method do you want to use? (Enter '1' for multi-port or '2' for one-port): " method_choice
        if [ "$method_choice" == "1" ]; then
            server_ip=$myip
            server_port="multi_port"

            arguments="--kharej --iran-ip:$server_ip --iran-port:443 --toip:127.0.0.1 --toport:multiport --password:$password --sni:$sni --keep-ufw --mux-width:2 --terminate:24"

        elif [ "$method_choice" == "2" ]; then
            read -p "Please Enter IP(IRAN) : " server_ip
            read -p "Please Enter Port(for connection between IRAN and Kharej) : " server_port

            if [ -f "/etc/systemd/system/Tunnel-reverse-$server_ip-$server_port.service" ]; then
                echo "This Tunnel is already installed."
                exit 1
            fi

            arguments="--kharej --iran-ip:$server_ip --iran-port:$server_port --toip:127.0.0.1 --toport:multiport --password:$password --sni:$sni --keep-ufw --mux-width:2 --terminate:24"
        else
            echo "Invalid choice. Please enter '1' or '2'."
            exit 1
        fi
    elif [ "$server_choice" == "1" ]; then
        read -p "Please Enter SNI (default : sheypoor.com): " sni
        sni=${sni:-sheypoor.com}

        read -p "Please Enter Password (Please choose the same password on both servers): " password

        read -p "Which method do you want to use? (Enter '1' for multi-port or '2' for one-port): " method_choice

        if [ "$method_choice" == "1" ]; then
            server_ip=$myip
            server_port="multi_port"

            if [ -f "/etc/systemd/system/Tunnel-reverse-$server_ip-$server_port.service" ]; then
                echo "This Tunnel is already installed. (If you want to connect this server to 2 or more servers, they must all be installed as one-port)"
                exit 1
            fi

            arguments="--iran --lport:23-65535 --sni:$sni --password:$password --keep-ufw --mux-width:2 --terminate:24"

        elif [ "$method_choice" == "2" ]; then
            read -p "Please Enter IP(Kharej) : " server_ip
            read -p "Please Enter Port(for connection between IRAN and Kharej (config port)) : " server_port

            if [ -f "/etc/systemd/system/Tunnel-reverse-$server_ip-$server_port.service" ]; then
                echo "This Tunnel is already installed."
                exit 1
            fi

            arguments="--iran --lport:$server_port --sni:$sni --password:$password --keep-ufw --mux-width:2 --terminate:24"

        else
            echo "Invalid choice. Please enter '1' or '2'."
            exit 1
        fi
    else
        echo "Invalid choice. Please enter '1' or '2'."
        exit 1
    fi

    cat <<EOL >Tunnel-reverse-$server_ip-$server_port.service
[Unit]
Description=Tunnel-reverse-$server_ip-$server_port

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
    sudo systemctl start Tunnel-reverse-$server_ip-$server_port.service
    sudo systemctl enable Tunnel-reverse-$server_ip-$server_port.service
    echo "This Tunnel with name (Tunnel-reverse-$server_ip-$server_port) was successfully installed"
}

remove_reverse() {
    read -p "Please Enter IP(Kharej or IRAN) : " server_ip
    read -p "Please Enter Port(for connection between IRAN and Kharej) : " server_port

    if [ ! -f "/etc/systemd/system/Tunnel-reverse-$server_ip-$server_port.service" ]; then
        echo "This Tunnel is not installed."
        return
    fi

    sudo systemctl stop Tunnel-reverse-$server_ip-$server_port.service
    sudo systemctl disable Tunnel-reverse-$server_ip-$server_port.service

    sudo rm /etc/systemd/system/Tunnel-reverse-$server_ip-$server_port.service
    sudo systemctl reset-failed
}

uninstall_reverse() {
    echo "Uninstalling..."

    files=$(ls -1A /etc/systemd/system/Tunnel-reverse-* 2>/dev/null)

    if [ ! -z "$files" ]; then
        for file in $files; do
            server_ip=$(echo $file | cut -d'-' -f3)
            server_port=$(echo $file | cut -d'-' -f4 | sed 's/\.service//')

            sudo systemctl stop Tunnel-reverse-$server_ip-$server_port.service
            sudo systemctl disable Tunnel-reverse-$server_ip-$server_port.service

            sudo rm /etc/systemd/system/Tunnel-reverse-$server_ip-$server_port.service
        done
    fi

    sudo systemctl reset-failed

    sudo rm RTT
    sudo rm install.sh 2>/dev/null

    echo "Uninstallation completed successfully."
}

start_tunnel_reverse() {
    read -p "Please Enter IP(Kharej or IRAN) : " server_ip
    read -p "Please Enter Port(for connection between IRAN and Kharej) : " server_port

    if sudo systemctl is-enabled --quiet Tunnel-reverse-$server_ip-$server_port.service; then
        sudo systemctl start Tunnel-reverse-$server_ip-$server_port.service >/dev/null 2>&1

        if sudo systemctl is-active --quiet Tunnel-reverse-$server_ip-$server_port.service; then
            echo "Tunnel service started."
        else
            echo "Tunnel service failed to start."
        fi
    else
        echo "Tunnel is not installed."
    fi
}

stop_tunnel_reverse() {
    read -p "Please Enter IP(Kharej or IRAN) : " server_ip
    read -p "Please Enter Port(for connection between IRAN and Kharej) : " server_port

    if sudo systemctl is-enabled --quiet Tunnel-reverse-$server_ip-$server_port.service; then
        sudo systemctl stop Tunnel-reverse-$server_ip-$server_port.service >/dev/null 2>&1

        if sudo systemctl is-active --quiet Tunnel-reverse-$server_ip-$server_port.service; then
            echo "Tunnel service failed to stop."
        else
            echo "Tunnel service stopped."
        fi
    else
        echo "Tunnel is not installed."
    fi
}

check_tunnel_status_reverse() {
    read -p "Please Enter IP(Kharej or IRAN) : " server_ip
    read -p "Please Enter Port(for connection between IRAN and Kharej) : " server_port

    if sudo systemctl is-active --quiet Tunnel-reverse-$server_ip-$server_port.service; then
        echo -e "${yellow}Tunnel is: ${green}[running ✔]${rest}"
    else
        echo -e "${yellow}Tunnel is:${red}[Not running ✗ ]${rest}"
    fi

    files=$(ls -1A /etc/systemd/system/Tunnel-reverse-* 2>/dev/null)

    if [ ! -z "$files" ]; then
        for file in $files; do
            server_ip=$(echo $file | cut -d'-' -f3)
            server_port=$(echo $file | cut -d'-' -f4 | sed 's/\.service//')

            echo -e "${yellow}IP: ${server_ip} | PORT: ${server_port}: ${green}[✔]${rest}"
        done
    else
        echo -e "${yellow}No tunnel found: ${red}[✗]${rest}"
    fi
}

remove_reverse_multiport() {

    files=$(ls -1A /etc/systemd/system/Tunnel-reverse-* 2>/dev/null)

    if [ ! -z "$files" ]; then
        for file in $files; do
            if [ "$port" = "multi_port" ]; then
                continue
            fi

            server_ip=$(echo $file | cut -d'-' -f3)
            server_port=$(echo $file | cut -d'-' -f4 | sed 's/\.service//')

            sudo systemctl stop Tunnel-reverse-$server_ip-$server_port.service
            sudo systemctl disable Tunnel-reverse-$server_ip-$server_port.service

            sudo rm /etc/systemd/system/Tunnel-reverse-$server_ip-$server_port.service
            sudo systemctl reset-failed

            echo "Uninstallation completed successfully."
            exit 1
        done
    fi

    echo "Multi-Port is not installed."
}

install_gost() {
    enable_bbr
    sysctl net.ipv4.ip_local_port_range="1024 65535"

    options=($'\e[36m1. \e[0mGost Tunnel By IP4'
        $'\e[36m2. \e[0mGost Tunnel By IP6')

    printf "\e[32mPlease Choice Your Options:\e[0m\n"
    printf "%s\n" "${options[@]}"
    read -p $'\e[97mYour choice: \e[0m' choice

    if [ "$choice" -eq 1 ]; then
        read -p $'\e[97mPlease enter the destination (Kharej) IP: \e[0m' destination_ip
    elif [ "$choice" -eq 2 ]; then
        read -p $'\e[97mPlease enter the destination (Kharej) IPv6: \e[0m' destination_ip
    fi

    read -p $'\e[32mPlease choose one of the options below:\n\e[0m\e[36m1. \e[0mEnter Manually Ports\n\e[36m2. \e[0mEnter Range Ports\e[32m\nYour choice: \e[0m' port_option

    if [ "$port_option" -eq 1 ]; then
        read -p $'\e[36mPlease enter the desired ports (separated by commas): \e[0m' ports
    elif [ "$port_option" -eq 2 ]; then
        read -p $'\e[36mPlease enter the port range (e.g., 54,65000): \e[0m' port_range

        IFS=',' read -ra port_array <<<"$port_range"

        if [ "${port_array[0]}" -lt 54 -o "${port_array[1]}" -gt 65000 ]; then
            echo $'\e[33mInvalid port range. Please enter a valid range starting from 54 and up to 65000.\e[0m'
            exit
        fi

        ports=$(seq -s, "${port_array[0]}" "${port_array[1]}")
    else
        echo $'\e[31mInvalid option. Exiting...\e[0m'
        exit
    fi

    read -p $'\e[32mSelect the protocol:\n\e[0m\e[36m1. \e[0mBy Tcp Protocol \n\e[36m2. \e[0mBy Grpc Protocol \e[32m\nYour choice: \e[0m' protocol_option

    if [ "$protocol_option" -eq 1 ]; then
        protocol="tcp"
    elif [ "$protocol_option" -eq 2 ]; then
        protocol="grpc"
    else
        echo $'\e[31mInvalid protocol option. Exiting...\e[0m'
        exit
    fi

    echo $'\e[32mYou chose option\e[0m' $choice
    echo $'\e[97mDestination IP:\e[0m' $destination_ip
    echo $'\e[97mPorts:\e[0m' $ports
    echo $'\e[97mProtocol:\e[0m' $protocol

    sudo apt install wget nano -y &&
        echo $'\e[32mInstalling Gost version 3.0.0, please wait...\e[0m'
    wget -O /tmp/linux_Gost_amd64.tar.gz https://github.com/NotMRGH/MRTunnel/releases/latest/download/linux_Gost_amd64.tar.gz
    tar -xvzf /tmp/linux_Gost_amd64.tar.gz -C /usr/local/bin/
    chmod +x /usr/local/bin/gost
    echo $'\e[32mGost installed successfully.\e[0m'

    exec_start_command="ExecStart=/usr/local/bin/gost"

    IFS=',' read -ra port_array <<<"$ports"
    port_count=${#port_array[@]}

    max_ports_per_file=12000

    file_count=$(((port_count + max_ports_per_file - 1) / max_ports_per_file))

    for ((file_index = 0; file_index < file_count; file_index++)); do
        cat <<EOL | sudo tee "/usr/lib/systemd/system/gost_$file_index.service" >/dev/null
[Unit]
Description=GO Simple Tunnel
After=network.target
Wants=network.target

[Service]
Type=simple
EOL

        exec_start_command="ExecStart=/usr/local/bin/gost"
        for ((i = file_index * max_ports_per_file; i < (file_index + 1) * max_ports_per_file && i < port_count; i++)); do
            port="${port_array[i]}"
            exec_start_command+=" -L=$protocol://:$port/[$destination_ip]:$port"
        done

        echo "$exec_start_command" | sudo tee -a "/usr/lib/systemd/system/gost_$file_index.service" >/dev/null

        cat <<EOL | sudo tee -a "/usr/lib/systemd/system/gost_$file_index.service" >/dev/null

[Install]
WantedBy=multi-user.target
EOL

        sudo systemctl daemon-reload
        sudo systemctl enable "gost_$file_index.service"
        sudo systemctl start "gost_$file_index.service"
    done

    echo $'\e[32mGost configuration applied successfully.\e[0m'
}

uninstall_gost() {
    read -p $'\e[91mWarning\e[33m: This will uninstall Gost and remove all related data. Are you sure you want to continue? (y/n): ' uninstall_confirm

    if [ "$uninstall_confirm" == "y" ]; then
        echo $'\e[32mUninstalling Gost in 3 seconds... \e[0m' && sleep 1 && echo $'\e[32m2... \e[0m' && sleep 1 && echo $'\e[32m1... \e[0m' && sleep 1 && {
            sudo rm -f /usr/bin/auto_restart_cronjob.sh

            crontab -l | grep -v '/usr/bin/auto_restart_cronjob.sh' | crontab -

            sudo systemctl daemon-reload
            sudo systemctl stop gost_*.service
            sudo rm -f /usr/local/bin/gost
            sudo rm -rf /etc/gost
            sudo rm -f /usr/lib/systemd/system/gost_*.service
            sudo rm -f /etc/systemd/system/multi-user.target.wants/gost_*.service
            echo $'\e[32mGost successfully uninstalled.\e[0m'
        }
    else
        echo $'\e[32mUninstallation canceled.\e[0m'
    fi
}

check_status_gost() {
    if command -v gost &>/dev/null; then
        echo $'\e[32mGost is installed. Checking configuration and status...\e[0m'

        systemctl list-unit-files | grep -q "gost_"
        if [ $? -eq 0 ]; then
            echo $'\e[32mGost is configured and active.\e[0m'

            for service_file in /usr/lib/systemd/system/gost_*.service; do
                service_info=$(awk -F'[-=:/\\[\\]]+' '/ExecStart=/ {print $14,$15,$22,$20,$23}' "$service_file")

                read -a info_array <<<"$service_info"

                echo -e "\e[97mIP:\e[0m ${info_array[0]} \e[97mPort:\e[0m ${info_array[1]},... \e[97mProtocol:\e[0m ${info_array[2]}"

            done
        else
            echo $'\e[33mGost is installed, but not configured or active.\e[0m'
        fi
    else
        echo $'\e[33mGost Tunnel is not installed. \e[0m'
    fi
}
add_new_ip_gost() {
    read -p $'\e[97mPlease enter the new destination (Kharej) IP 4 or 6: \e[0m' destination_ip
    read -p $'\e[36mPlease enter the new port (separated by commas): \e[0m' port
    read -p $'\e[32mSelect the protocol:\n\e[0m\e[36m1. \e[0mBy Tcp Protocol \n\e[36m2. \e[0mBy Grpc Protocol \e[32m\nYour choice: \e[0m' protocol_option

    if [ "$protocol_option" -eq 1 ]; then
        protocol="tcp"
    elif [ "$protocol_option" -eq 2 ]; then
        protocol="grpc"
    else
        echo $'\e[31mInvalid protocol option. Exiting...\e[0m'
        exit
    fi

    echo $'\e[32mYou chose option\e[0m' $choice
    echo $'\e[97mDestination IP:\e[0m' $destination_ip
    echo $'\e[97mPort(s):\e[0m' $port
    echo $'\e[97mProtocol:\e[0m' $protocol

    cat <<EOL | sudo tee "/usr/lib/systemd/system/gost_$destination_ip.service" >/dev/null
[Unit]
Description=GO Simple Tunnel
After=network.target
Wants=network.target

[Service]
Type=simple
EOL

    IFS=',' read -ra port_array <<<"$port"
    port_count=${#port_array[@]}

    max_ports_per_file=12000

    file_count=$(((port_count + max_ports_per_file - 1) / max_ports_per_file))

    for ((file_index = 0; file_index < file_count; file_index++)); do
        exec_start_command="ExecStart=/usr/local/bin/gost"
        for ((i = file_index * max_ports_per_file; i < (file_index + 1) * max_ports_per_file && i < port_count; i++)); do
            port="${port_array[i]}"
            exec_start_command+=" -L=$protocol://:$port/[$destination_ip]:$port"
        done

        echo "$exec_start_command" | sudo tee -a "/usr/lib/systemd/system/gost_$destination_ip.service" >/dev/null
    done

    cat <<EOL | sudo tee -a "/usr/lib/systemd/system/gost_$destination_ip.service" >/dev/null

[Install]
WantedBy=multi-user.target
EOL

    sudo systemctl daemon-reload
    sudo systemctl enable "gost_$destination_ip.service"
    sudo systemctl start "gost_$destination_ip.service"

    echo $'\e[32mGost configuration applied successfully.\e[0m'
    bash "$0"
}

auto_restart_gost() {
    echo $'\e[32mChoose Auto Restart option:\e[0m'
    echo $'\e[36m1. \e[0mEnable Auto Restart'
    echo $'\e[36m2. \e[0mDisable Auto Restart'

    read -p $'\e[97mYour choice: \e[0m' auto_restart_option

    case "$auto_restart_option" in
    1)
        echo $'\e[32mAuto Restart Enabled.\e[0m'
        sudo at -l | awk '{print $1}' | xargs -I {} atrm {}
        read -p $'\e[97mEnter the restart time in hours: \e[0m' restart_time_hours

        restart_time_minutes=$((restart_time_hours * 60))

        echo -e "#!/bin/bash\n\nsudo systemctl daemon-reload\nsudo systemctl restart gost_*.service" | sudo tee /usr/bin/auto_restart_cronjob.sh >/dev/null

        sudo chmod +x /usr/bin/auto_restart_cronjob.sh

        crontab -l | grep -v '/usr/bin/auto_restart_cronjob.sh' | crontab -

        (
            crontab -l
            echo "0 */$restart_time_hours * * * /usr/bin/auto_restart_cronjob.sh"
        ) | crontab -

        echo $'\e[32mAuto Restart scheduled successfully.\e[0m'
        ;;
    2)
        echo $'\e[32mAuto Restart Disabled.\e[0m'
        sudo rm -f /usr/bin/auto_restart_cronjob.sh
        crontab -l | grep -v '/usr/bin/auto_restart_cronjob.sh' | crontab -

        echo $'\e[32mAuto Restart disabled successfully.\e[0m'
        ;;
    *)
        echo $'\e[31mInvalid choice. Exiting...\e[0m'
        exit
        ;;
    esac
}

clear

echo "
\$\$\      \$\$\ \$\$\$\$\$\$\$\        \$\$\$\$\$\$\$\$\                                      \$\$\ 
\$\$\$\    \$\$\$ |\$\$  __\$\$\       \__\$\$  __|                                     \$\$ |
\$\$\$\$\  \$\$\$\$ |\$\$ |  \$\$ |         \$\$ |\$\$\   \$\$\ \$\$\$\$\$\$\$\  \$\$\$\$\$\$\$\   \$\$\$\$\$\$\  \$\$ |
\$\$\\$\$\\$\$ \$\$ |\$\$\$\$\$\$\$  |         \$\$ |\$\$ |  \$\$ |\$\$  __\$\$\ \$\$  __\$\$\ \$\$  __\$\$\ \$\$ |
\$\$ \\$\$\$  \$\$ |\$\$  __\$\$<          \$\$ |\$\$ |  \$\$ |\$\$ |  \$\$ |\$\$ |  \$\$ |\$\$\$\$\$\$\$\$ |\$\$ |
\$\$ |\\$  /\$\$ |\$\$ |  \$\$ |         \$\$ |\$\$ |  \$\$ |\$\$ |  \$\$ |\$\$ |  \$\$ |\$\$   ____|\$\$ |
\$\$ | \_/ \$\$ |\$\$ |  \$\$ |         \$\$ |\\$\$\$\$\$\$  |\$\$ |  \$\$ |\$\$ |  \$\$ |\\$\$\$\$\$\$\$\ \$\$ |
\__|     \__|\__|  \__|         \__| \______/ \__|  \__|\__|  \__| \_______|\__|     
                                                                                
                                                                                
                                                                                                                                                                                                                         
"
echo -e "${cyan}By --> NotMR_GH * Github.com/NotMRGH * ${rest}"
echo -e "Your IP is: ${cyan}($myip)${rest} "
echo -e "${yellow}******************************${rest}"
echo -e " ${purple}--------#- Reverse Tls Tunnel -#--------${rest}"
echo -e "${green}1) Install${rest}"
echo -e "${red}2) Remove multiport${rest}"
echo -e "${red}3) Uninstall All${rest}"
echo -e "${green}4) Start${rest}"
echo -e "${red}5) Stop${rest}"
echo -e "${yellow}6) Check Status${rest}"
echo -e "${green}7) Add Tunnel${rest}"
echo -e "${red}8) Remove Tunnel${rest}"
echo -e " ${purple}--------#- Gost Tunnel -#--------${rest}"
echo -e "${green}9) Install${rest}"
echo -e "${red}10) Uninstall${rest}"
echo -e "${yellow}11) Check Status${rest}"
echo -e "${green}12) Add New IP${rest}"
echo -e "${yellow}13) Auto Restart Gost${rest}"
echo -e "${red}0) Exit${rest}"
read -p "Please choose: " choice

case $choice in
1)
    install_reverse
    ;;
2)
    remove_reverse_multiport
    ;;
3)
    uninstall_reverse
    ;;
4)
    start_tunnel_reverse
    ;;
5)
    stop_tunnel_reverse
    ;;
6)
    check_tunnel_status_reverse
    ;;
7)
    add_reverse
    ;;
8)
    remove_reverse
    ;;
9)
    install_gost
    ;;
10)
    uninstall_gost
    ;;
11)
    check_status_gost
    ;;
12)
    add_new_ip_gost
    ;;
13)
    auto_restart_gost
    ;;
0)
    exit
    ;;
*)
    echo "Invalid choice. Please try again."
    ;;
esac
