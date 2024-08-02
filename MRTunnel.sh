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

    if ! grep -q "net.core.default_qdisc=fq" /etc/sysctl.conf && grep -q "net.ipv4.tcp_congestion_control=bbr" /etc/sysctl.conf; then
        echo -e "${green}instaling BBR${plain}"
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

    if [ -f /root/RTT ]; then
        echo "Script is already installed"
        exit 1
    fi

    check_dependencies_reverse
    install_rtt
    enable_bbr

    echo -e "${green}Tunnel installed successfully${plain}${rest}"
}

add_reverse() {

    if [ ! -f /root/RTT ]; then
        echo "Script not installed"
        exit 1
    fi

    files=$(ls -1A /etc/systemd/system/Tunnel-reverse-* 2>/dev/null)

    cd /etc/systemd/system

    read -p "Which server do you want to use? (Enter '1' for Iran(internal-server) or '2' for Kharej(external-server): " server_choice
    if [ "$server_choice" == "2" ]; then

        read -p "Please Enter SNI (default : sheypoor.com): " sni
        sni=${sni:-sheypoor.com}

        read -p "Please Enter Password (Please choose the same password on both servers): " password
        read -p "Please Enter IP(IRAN) : " server_ip
        read -p "Please Enter Port(for connection between IRAN and Kharej) : " server_port

        if [ -f "/etc/systemd/system/Tunnel-reverse-$server_ip-$server_port.service" ]; then
            echo "This Tunnel is already installed."
            exit 1
        fi

        arguments="--kharej --iran-ip:$server_ip --iran-port:$server_port --toip:127.0.0.1 --toport:multiport --password:$password --sni:$sni --keep-ufw --mux-width:2 --terminate:24"
    elif [ "$server_choice" == "1" ]; then
        read -p "Please Enter SNI (default : sheypoor.com): " sni
        sni=${sni:-sheypoor.com}

        read -p "Please Enter Password (Please choose the same password on both servers): " password
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

    if [ ! -f /root/RTT ]; then
        echo "Script not installed"
        exit 1
    fi

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

    read -p $'\e[32mSelect the protocol:\n\e[0m\e[36m1. \e[0mBy "Tcp" Protocol \n\e[36m2. \e[0mBy "Udp" Protocol \n\e[36m3. \e[0mBy "Grpc" Protocol \e[32m\nYour choice: \e[0m' protocol_option

    if [ "$protocol_option" -eq 1 ]; then
        protocol="tcp"
    elif [ "$protocol_option" -eq 2 ]; then
        protocol="udp"
    elif [ "$protocol_option" -eq 3 ]; then
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
Environment="GOST_LOGGER_LEVEL=fatal"
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

        sudo systemctl enable "gost_$file_index.service"
        sudo systemctl start "gost_$file_index.service"
        sudo systemctl daemon-reload
        sudo systemctl restart "gost_$file_index.service"
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

                a=$(awk '/\/usr\/local\/bin\/gost /{print}' "$service_file")

                for s in $(echo $a | tr "=" "\n"); do
                    if [[ $s == "/usr/local/bin/gost -L" ]]; then
                        continue
                    fi

                    protocol=$(echo $s | cut -d ":" -f1)
                    port=$(echo $s | cut -d ":" -f3 | cut -d "/" -f1)
                    ip=$(echo $s | cut -d "[" -f2 | cut -d "]" -f1)

                    if [[ $protocol == "-L" ]]; then
                        continue
                    fi

                    if [[ $protocol == "/usr/local/bin/gost" ]]; then
                        continue
                    fi

                    if [[ $protocol == "ExecStart" ]]; then
                        continue
                    fi

                    echo -e "\e[97mIP:\e[0m ${ip} \e[97mPort:\e[0m ${port} \e[97mProtocol:\e[0m ${protocol}"
                done
            done
        else
            echo $'\e[33mGost is installed, but not configured or active.\e[0m'
        fi
    else
        echo $'\e[33mGost Tunnel is not installed. \e[0m'
    fi

    read -n 1 -s -r -p $'\e[36m0. \e[0mBack to menu: \e[0m' choice

    if [ "$choice" -eq 0 ]; then
        bash "$0"
    fi
}

add_new_ip_gost() {
    read -p $'\e[97mPlease enter the new destination (Kharej) IP 4 or 6: \e[0m' destination_ip
    read -p $'\e[36mPlease enter the new port (separated by commas): \e[0m' port
    read -p $'\e[32mSelect the protocol:\n\e[0m\e[36m1. \e[0mBy "Tcp" Protocol \n\e[36m2. \e[0mBy "Udp" Protocol \n\e[36m3. \e[0mBy "Grpc" Protocol \e[32m\nYour choice: \e[0m' protocol_option

    if [ "$protocol_option" -eq 1 ]; then
        protocol="tcp"
    elif [ "$protocol_option" -eq 2 ]; then
        protocol="udp"
    elif [ "$protocol_option" -eq 3 ]; then
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

trap _exit INT QUIT TERM

_red() {
    printf '\033[0;31;31m%b\033[0m' "$1"
}

_green() {
    printf '\033[0;31;32m%b\033[0m' "$1"
}

_yellow() {
    printf '\033[0;31;33m%b\033[0m' "$1"
}

_blue() {
    printf '\033[0;31;36m%b\033[0m' "$1"
}

_exists() {
    local cmd="$1"
    if eval type type >/dev/null 2>&1; then
        eval type "$cmd" >/dev/null 2>&1
    elif command >/dev/null 2>&1; then
        command -v "$cmd" >/dev/null 2>&1
    else
        which "$cmd" >/dev/null 2>&1
    fi
    local rt=$?
    return ${rt}
}

_exit() {
    _red "\nThe script has been terminated. Cleaning up files...\n"
    # clean up
    rm -fr speedtest.tgz speedtest-cli benchtest_*
    exit 1
}

get_opsy() {
    [ -f /etc/redhat-release ] && awk '{print $0}' /etc/redhat-release && return
    [ -f /etc/os-release ] && awk -F'[= "]' '/PRETTY_NAME/{print $3,$4,$5}' /etc/os-release && return
    [ -f /etc/lsb-release ] && awk -F'[="]+' '/DESCRIPTION/{print $2}' /etc/lsb-release && return
}

next() {
    printf "%-70s\n" "-" | sed 's/\s/-/g'
}

speed_test() {
    local nodeName="$2"
    if [ -z "$1" ]; then
        ./speedtest-cli/speedtest --progress=no --accept-license --accept-gdpr >./speedtest-cli/speedtest.log 2>&1
    else
        ./speedtest-cli/speedtest --progress=no --server-id="$1" --accept-license --accept-gdpr >./speedtest-cli/speedtest.log 2>&1
    fi
    if [ $? -eq 0 ]; then
        local dl_speed up_speed latency
        dl_speed=$(awk '/Download/{print $3" "$4}' ./speedtest-cli/speedtest.log)
        up_speed=$(awk '/Upload/{print $3" "$4}' ./speedtest-cli/speedtest.log)
        latency=$(awk '/Latency/{print $3" "$4}' ./speedtest-cli/speedtest.log)
        if [[ -n "${dl_speed}" && -n "${up_speed}" && -n "${latency}" ]]; then
            printf "\033[0;33m%-18s\033[0;32m%-18s\033[0;31m%-20s\033[0;36m%-12s\033[0m\n" " ${nodeName}" "${up_speed}" "${dl_speed}" "${latency}"
        fi
    fi
}

io_test() {
    (LANG=C dd if=/dev/zero of=benchtest_$$ bs=512k count="$1" conv=fdatasync && rm -f benchtest_$$) 2>&1 | awk -F '[,，]' '{io=$NF} END { print io}' | sed 's/^[ \t]*//;s/[ \t]*$//'
}

calc_size() {
    local raw=$1
    local total_size=0
    local num=1
    local unit="KB"
    if ! [[ ${raw} =~ ^[0-9]+$ ]]; then
        echo ""
        return
    fi
    if [ "${raw}" -ge 1073741824 ]; then
        num=1073741824
        unit="TB"
    elif [ "${raw}" -ge 1048576 ]; then
        num=1048576
        unit="GB"
    elif [ "${raw}" -ge 1024 ]; then
        num=1024
        unit="MB"
    elif [ "${raw}" -eq 0 ]; then
        echo "${total_size}"
        return
    fi
    total_size=$(awk 'BEGIN{printf "%.1f", '"$raw"' / '$num'}')
    echo "${total_size} ${unit}"
}

to_kibyte() {
    local raw=$1
    awk 'BEGIN{printf "%.0f", '"$raw"' / 1024}'
}

calc_sum() {
    local arr=("$@")
    local s
    s=0
    for i in "${arr[@]}"; do
        s=$((s + i))
    done
    echo ${s}
}

status_test() {
    ! _exists "wget" && _red "Error: wget command not found.\n" && exit 1
    ! _exists "free" && _red "Error: free command not found.\n" && exit 1
    _exists "curl" && local_curl=true
    [[ -n ${local_curl} ]] && ip_check_cmd="curl -s -m 4" || ip_check_cmd="wget -qO- -T 4"
    ipv4_check=$( (ping -4 -c 1 -W 4 ipv4.google.com >/dev/null 2>&1 && echo true) || ${ip_check_cmd} -4 icanhazip.com 2>/dev/null)
    ipv6_check=$( (ping -6 -c 1 -W 4 ipv6.google.com >/dev/null 2>&1 && echo true) || ${ip_check_cmd} -6 icanhazip.com 2>/dev/null)
    if [[ -z "$ipv4_check" && -z "$ipv6_check" ]]; then
        _yellow "Warning: Both IPv4 and IPv6 connectivity were not detected.\n"
    fi
    [[ -z "$ipv4_check" ]] && online="$(_red "\xe2\x9c\x97 Offline")" || online="$(_green "\xe2\x9c\x93 Online")"
    [[ -z "$ipv6_check" ]] && online+=" / $(_red "\xe2\x9c\x97 Offline")" || online+=" / $(_green "\xe2\x9c\x93 Online")"
    start_time=$(date +%s)
    cname=$(awk -F: '/model name/ {name=$2} END {print name}' /proc/cpuinfo | sed 's/^[ \t]*//;s/[ \t]*$//')
    cores=$(awk -F: '/^processor/ {core++} END {print core}' /proc/cpuinfo)
    freq=$(awk -F'[ :]' '/cpu MHz/ {print $4;exit}' /proc/cpuinfo)
    ccache=$(awk -F: '/cache size/ {cache=$2} END {print cache}' /proc/cpuinfo | sed 's/^[ \t]*//;s/[ \t]*$//')
    cpu_aes=$(grep -i 'aes' /proc/cpuinfo)
    cpu_virt=$(grep -Ei 'vmx|svm' /proc/cpuinfo)
    tram=$(
        LANG=C
        free | awk '/Mem/ {print $2}'
    )
    tram=$(calc_size "$tram")
    uram=$(
        LANG=C
        free | awk '/Mem/ {print $3}'
    )
    uram=$(calc_size "$uram")
    swap=$(
        LANG=C
        free | awk '/Swap/ {print $2}'
    )
    swap=$(calc_size "$swap")
    uswap=$(
        LANG=C
        free | awk '/Swap/ {print $3}'
    )
    uswap=$(calc_size "$uswap")
    up=$(awk '{a=$1/86400;b=($1%86400)/3600;c=($1%3600)/60} {printf("%d days, %d hour %d min\n",a,b,c)}' /proc/uptime)
    if _exists "w"; then
        load=$(
            LANG=C
            w | head -1 | awk -F'load average:' '{print $2}' | sed 's/^[ \t]*//;s/[ \t]*$//'
        )
    elif _exists "uptime"; then
        load=$(
            LANG=C
            uptime | head -1 | awk -F'load average:' '{print $2}' | sed 's/^[ \t]*//;s/[ \t]*$//'
        )
    fi
    opsy=$(get_opsy)
    arch=$(uname -m)
    if _exists "getconf"; then
        lbit=$(getconf LONG_BIT)
    else
        echo "${arch}" | grep -q "64" && lbit="64" || lbit="32"
    fi
    kern=$(uname -r)
    in_kernel_no_swap_total_size=$(
        LANG=C
        df -t simfs -t ext2 -t ext3 -t ext4 -t btrfs -t xfs -t vfat -t ntfs --total 2>/dev/null | grep total | awk '{ print $2 }'
    )
    swap_total_size=$(free -k | grep Swap | awk '{print $2}')
    zfs_total_size=$(to_kibyte "$(calc_sum "$(zpool list -o size -Hp 2>/dev/null)")")
    disk_total_size=$(calc_size $((swap_total_size + in_kernel_no_swap_total_size + zfs_total_size)))
    in_kernel_no_swap_used_size=$(
        LANG=C
        df -t simfs -t ext2 -t ext3 -t ext4 -t btrfs -t xfs -t vfat -t ntfs --total 2>/dev/null | grep total | awk '{ print $3 }'
    )
    swap_used_size=$(free -k | grep Swap | awk '{print $3}')
    zfs_used_size=$(to_kibyte "$(calc_sum "$(zpool list -o allocated -Hp 2>/dev/null)")")
    disk_used_size=$(calc_size $((swap_used_size + in_kernel_no_swap_used_size + zfs_used_size)))
    tcpctrl=$(sysctl net.ipv4.tcp_congestion_control | awk -F ' ' '{print $3}')
    _exists "dmesg" && virtualx="$(dmesg 2>/dev/null)"
    if _exists "dmidecode"; then
        sys_manu="$(dmidecode -s system-manufacturer 2>/dev/null)"
        sys_product="$(dmidecode -s system-product-name 2>/dev/null)"
        sys_ver="$(dmidecode -s system-version 2>/dev/null)"
    else
        sys_manu=""
        sys_product=""
        sys_ver=""
    fi
    if grep -qa docker /proc/1/cgroup; then
        virt="Docker"
    elif grep -qa lxc /proc/1/cgroup; then
        virt="LXC"
    elif grep -qa container=lxc /proc/1/environ; then
        virt="LXC"
    elif [[ -f /proc/user_beancounters ]]; then
        virt="OpenVZ"
    elif [[ "${virtualx}" == *kvm-clock* ]]; then
        virt="KVM"
    elif [[ "${sys_product}" == *KVM* ]]; then
        virt="KVM"
    elif [[ "${sys_manu}" == *QEMU* ]]; then
        virt="KVM"
    elif [[ "${cname}" == *KVM* ]]; then
        virt="KVM"
    elif [[ "${cname}" == *QEMU* ]]; then
        virt="KVM"
    elif [[ "${virtualx}" == *"VMware Virtual Platform"* ]]; then
        virt="VMware"
    elif [[ "${sys_product}" == *"VMware Virtual Platform"* ]]; then
        virt="VMware"
    elif [[ "${virtualx}" == *"Parallels Software International"* ]]; then
        virt="Parallels"
    elif [[ "${virtualx}" == *VirtualBox* ]]; then
        virt="VirtualBox"
    elif [[ -e /proc/xen ]]; then
        if grep -q "control_d" "/proc/xen/capabilities" 2>/dev/null; then
            virt="Xen-Dom0"
        else
            virt="Xen-DomU"
        fi
    elif [ -f "/sys/hypervisor/type" ] && grep -q "xen" "/sys/hypervisor/type"; then
        virt="Xen"
    elif [[ "${sys_manu}" == *"Microsoft Corporation"* ]]; then
        if [[ "${sys_product}" == *"Virtual Machine"* ]]; then
            if [[ "${sys_ver}" == *"7.0"* || "${sys_ver}" == *"Hyper-V" ]]; then
                virt="Hyper-V"
            else
                virt="Microsoft Virtual Machine"
            fi
        fi
    else
        virt="Dedicated"
    fi
    clear
    echo "-------------------- MRTunnel -------------------"
    next
    if [ -n "$cname" ]; then
        echo " CPU Model          : $(_blue "$cname")"
    else
        echo " CPU Model          : $(_blue "CPU model not detected")"
    fi
    if [ -n "$freq" ]; then
        echo " CPU Cores          : $(_blue "$cores @ $freq MHz")"
    else
        echo " CPU Cores          : $(_blue "$cores")"
    fi
    if [ -n "$ccache" ]; then
        echo " CPU Cache          : $(_blue "$ccache")"
    fi
    if [ -n "$cpu_aes" ]; then
        echo " AES-NI             : $(_green "\xe2\x9c\x93 Enabled")"
    else
        echo " AES-NI             : $(_red "\xe2\x9c\x97 Disabled")"
    fi
    if [ -n "$cpu_virt" ]; then
        echo " VM-x/AMD-V         : $(_green "\xe2\x9c\x93 Enabled")"
    else
        echo " VM-x/AMD-V         : $(_red "\xe2\x9c\x97 Disabled")"
    fi
    echo " Total Disk         : $(_yellow "$disk_total_size") $(_blue "($disk_used_size Used)")"
    echo " Total Mem          : $(_yellow "$tram") $(_blue "($uram Used)")"
    if [ "$swap" != "0" ]; then
        echo " Total Swap         : $(_blue "$swap ($uswap Used)")"
    fi
    echo " System uptime      : $(_blue "$up")"
    echo " Load average       : $(_blue "$load")"
    echo " OS                 : $(_blue "$opsy")"
    echo " Arch               : $(_blue "$arch ($lbit Bit)")"
    echo " Kernel             : $(_blue "$kern")"
    echo " TCP CC             : $(_yellow "$tcpctrl")"
    echo " Virtualization     : $(_blue "$virt")"
    echo " IPv4/IPv6          : $online"
    local org city country region
    org="$(wget -q -T10 -O- ipinfo.io/org)"
    city="$(wget -q -T10 -O- ipinfo.io/city)"
    country="$(wget -q -T10 -O- ipinfo.io/country)"
    region="$(wget -q -T10 -O- ipinfo.io/region)"
    if [[ -n "${org}" ]]; then
        echo " Organization       : $(_blue "${org}")"
    fi
    if [[ -n "${city}" && -n "${country}" ]]; then
        echo " Location           : $(_blue "${city} / ${country}")"
    fi
    if [[ -n "${region}" ]]; then
        echo " Region             : $(_yellow "${region}")"
    fi
    if [[ -z "${org}" ]]; then
        echo " Region             : $(_red "No ISP detected")"
    fi
    next
    freespace=$(df -m . | awk 'NR==2 {print $4}')
    if [ -z "${freespace}" ]; then
        freespace=$(df -m . | awk 'NR==3 {print $3}')
    fi
    if [ "${freespace}" -gt 1024 ]; then
        writemb=2048
        io1=$(io_test ${writemb})
        echo " I/O Speed(1st run) : $(_yellow "$io1")"
        io2=$(io_test ${writemb})
        echo " I/O Speed(2nd run) : $(_yellow "$io2")"
        io3=$(io_test ${writemb})
        echo " I/O Speed(3rd run) : $(_yellow "$io3")"
        ioraw1=$(echo "$io1" | awk 'NR==1 {print $1}')
        [[ "$(echo "$io1" | awk 'NR==1 {print $2}')" == "GB/s" ]] && ioraw1=$(awk 'BEGIN{print '"$ioraw1"' * 1024}')
        ioraw2=$(echo "$io2" | awk 'NR==1 {print $1}')
        [[ "$(echo "$io2" | awk 'NR==1 {print $2}')" == "GB/s" ]] && ioraw2=$(awk 'BEGIN{print '"$ioraw2"' * 1024}')
        ioraw3=$(echo "$io3" | awk 'NR==1 {print $1}')
        [[ "$(echo "$io3" | awk 'NR==1 {print $2}')" == "GB/s" ]] && ioraw3=$(awk 'BEGIN{print '"$ioraw3"' * 1024}')
        ioall=$(awk 'BEGIN{print '"$ioraw1"' + '"$ioraw2"' + '"$ioraw3"'}')
        ioavg=$(awk 'BEGIN{printf "%.1f", '"$ioall"' / 3}')
        echo " I/O Speed(average) : $(_yellow "$ioavg MB/s")"
    else
        echo " $(_red "Not enough space for I/O Speed test!")"
    fi
    next
    if [ ! -e "./speedtest-cli/speedtest" ]; then
        sys_bit=""
        local sysarch
        sysarch="$(uname -m)"
        if [ "${sysarch}" = "unknown" ] || [ "${sysarch}" = "" ]; then
            sysarch="$(arch)"
        fi
        if [ "${sysarch}" = "x86_64" ]; then
            sys_bit="x86_64"
        fi
        if [ "${sysarch}" = "i386" ] || [ "${sysarch}" = "i686" ]; then
            sys_bit="i386"
        fi
        if [ "${sysarch}" = "armv8" ] || [ "${sysarch}" = "armv8l" ] || [ "${sysarch}" = "aarch64" ] || [ "${sysarch}" = "arm64" ]; then
            sys_bit="aarch64"
        fi
        if [ "${sysarch}" = "armv7" ] || [ "${sysarch}" = "armv7l" ]; then
            sys_bit="armhf"
        fi
        if [ "${sysarch}" = "armv6" ]; then
            sys_bit="armel"
        fi
        [ -z "${sys_bit}" ] && _red "Error: Unsupported system architecture (${sysarch}).\n" && exit 1
        url1="https://install.speedtest.net/app/cli/ookla-speedtest-1.2.0-linux-${sys_bit}.tgz"
        url2="https://dl.lamp.sh/files/ookla-speedtest-1.2.0-linux-${sys_bit}.tgz"
        if ! wget --no-check-certificate -q -T10 -O speedtest.tgz ${url1}; then
            if ! wget --no-check-certificate -q -T10 -O speedtest.tgz ${url2}; then
                _red "Error: Failed to download speedtest-cli.\n" && exit 1
            fi
        fi
        mkdir -p speedtest-cli && tar zxf speedtest.tgz -C ./speedtest-cli && chmod +x ./speedtest-cli/speedtest
        rm -f speedtest.tgz
    fi
    printf "%-18s%-18s%-20s%-12s\n" " Node Name" "Upload Speed" "Download Speed" "Latency"
    speed_test '' 'Speedtest.net'
    speed_test '21541' 'Los Angeles, US'
    speed_test '43860' 'Dallas, US'
    speed_test '40879' 'Montreal, CA'
    speed_test '24215' 'Paris, FR'
    speed_test '28922' 'Amsterdam, NL'
    speed_test '24447' 'Shanghai, CN'
    speed_test '5530' 'Chongqing, CN'
    speed_test '60572' 'Guangzhou, CN'
    speed_test '32155' 'Hongkong, CN'
    speed_test '23647' 'Mumbai, IN'
    speed_test '13623' 'Singapore, SG'
    speed_test '21569' 'Tokyo, JP'
    rm -fr speedtest-cli
    next
    end_time=$(date +%s)
    time=$((end_time - start_time))
    if [ ${time} -gt 60 ]; then
        min=$((time / 60))
        sec=$((time % 60))
        echo " Finished in        : ${min} min ${sec} sec"
    else
        echo " Finished in        : ${time} sec"
    fi
    date_time=$(date '+%Y-%m-%d %H:%M:%S %Z')
    echo " Timestamp          : $date_time"
    next
}

add_6to4() {
    read -p "Which server do you want to use? (Enter '1' for Iran(internal-server) or '2' for Kharej(external-server): " server_choice
    if [ "$server_choice" == "1" ]; then
        read -p "Please Enter IPv4 IRAN : " ip_iran
        read -p "Please Enter IPv4 KHAREJ " ip_kharej

        read -p "Please Enter Local IPv4 IRAN : " ip_local_iran_v4
        read -p "Please Enter Local IPv4 KHAREJ : " ip_local_kharej_v4

        read -p "Please Enter Local IPv6 IRAN : " ip_local_iran_v6
        read -p "Please Enter Local IPv6 KHAREJ : " ip_local_kharej_v6

        read -p "Please Enter Tunnel Name : " tunnel_name
        read -p "Please Enter Tunnel Port : " tunnel_port

        # Create tunnels
        ip tunnel add ${tunnel_name}1 mode sit remote $ip_kharej local $ip_iran
        ip -6 addr add $ip_local_iran_v6/64 dev ${tunnel_name}1
        ip link set ${tunnel_name}1 mtu 1480
        ip link set ${tunnel_name}1 up

        # Configure NAT rules
        ip -6 tunnel add ${tunnel_name}2 mode ipip6 remote $ip_local_kharej_v6 local $ip_local_iran_v6
        ip addr add $ip_local_iran_v4/30 dev ${tunnel_name}2
        ip link set ${tunnel_name}2 mtu 1440
        ip link set ${tunnel_name}2 up

        # Configure iptables
        sysctl net.ipv4.ip_forward=1
        iptables -t nat -A PREROUTING -p tcp --dport $tunnel_port -j DNAT --to-destination $ip_local_iran_v4
        iptables -t nat -A PREROUTING -j DNAT --to-destination $ip_local_kharej_v4
        iptables -t nat -A POSTROUTING -j MASQUERADE

    elif [ "$server_choice" == "2" ]; then

        read -p "Please Enter IPv4 IRAN : " ip_iran
        read -p "Please Enter IPv4 KHAREJ " ip_kharej

        read -p "Please Enter Local IPv4 KHAREJ : " ip_local_kharej_v4

        read -p "Please Enter Local IPv6 IRAN : " ip_local_iran_v6
        read -p "Please Enter Local IPv6 KHAREJ : " ip_local_kharej_v6

        read -p "Please Enter Tunnel Name : " tunnel_name

        # Create tunnels
        ip tunnel add ${tunnel_name}1 mode sit remote $ip_iran local $ip_kharej
        ip -6 addr add $ip_local_kharej_v6/64 dev ${tunnel_name}1
        ip link set ${tunnel_name}1 mtu 1480
        ip link set ${tunnel_name}1 up

        # Configure NAT rules
        ip -6 tunnel add ${tunnel_name}2 mode ipip6 remote $ip_local_iran_v6 local $ip_local_kharej_v6
        ip addr add $ip_local_kharej_v4/30 dev ${tunnel_name}2
        ip link set ${tunnel_name}2 mtu 1440
        ip link set ${tunnel_name}2 up

    else
        echo "Invalid choice. Please enter '1' or '2'."
        exit 1
    fi
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
echo -e "${red}2) Uninstall All${rest}"
echo -e "${green}3) Start${rest}"
echo -e "${red}4) Stop${rest}"
echo -e "${yellow}5) Check Status${rest}"
echo -e "${green}6) Add Tunnel${rest}"
echo -e "${red}7) Remove Tunnel${rest}"
echo -e " ${purple}--------#- Gost Tunnel -#--------${rest}"
echo -e "${green}8) Install${rest}"
echo -e "${red}9) Uninstall${rest}"
echo -e "${yellow}10) Check Status${rest}"
echo -e "${green}11) Add New IP${rest}"
echo -e "${yellow}12) Auto Restart Gost${rest}"
echo -e " ${purple}--------#- 6to4 Tunnel -#--------${rest}"
echo -e "${green}13) Add Tunnel${rest}"
echo -e "${red}14) Remove Tunnel${rest}"
echo -e " ${purple}--------#- Optimizer -#--------${rest}"
echo -e "${green}15) Status${rest}"
echo -e "${red}0) Exit${rest}"
read -p "Please choose: " choice

case $choice in
1)
    install_reverse
    ;;
2)
    uninstall_reverse
    ;;
3)
    start_tunnel_reverse
    ;;
4)
    stop_tunnel_reverse
    ;;
5)
    check_tunnel_status_reverse
    ;;
6)
    add_reverse
    ;;
7)
    remove_reverse
    ;;
8)
    install_gost
    ;;
9)
    uninstall_gost
    ;;
10)
    check_status_gost
    ;;
11)
    add_new_ip_gost
    ;;
12)
    auto_restart_gost
    ;;
13)
    add_6to4
    ;;
14)
    status_test
    ;;
15)
    status_test
    ;;
0)
    exit
    ;;
*)
    echo "Invalid choice. Please try again."
    ;;
esac
