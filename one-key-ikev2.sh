#! /bin/bash
set -e
set -o pipefail
umask 077
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH
#===============================================================================================
#   System Required:  Debian 12+ or RHEL-compatible Linux 8+
#   Description:  Install IKEv2 VPN
#   Author: quericy
#   Intro:  https://quericy.me/blog/699
#===============================================================================================

[ ! -t 1 ] || clear
VER=1.2.0
echo "#############################################################"
echo "# Install IKEv2 VPN for Debian 12+ or RHEL-compatible Linux 8+"
echo "# Intro: https://quericy.me/blog/699"
echo "#"
echo "# Author:quericy"
echo "#"
echo "# Version:$VER"
echo "#############################################################"
echo ""

__INTERACTIVE=""
if [ -t 1 ] ; then
    __INTERACTIVE="1"
fi

__green(){
    if [ "$__INTERACTIVE" ] ; then
        printf '\033[1;31;32m'
    fi
    printf -- "$1"
    if [ "$__INTERACTIVE" ] ; then
        printf '\033[0m'
    fi
}

__red(){
    if [ "$__INTERACTIVE" ] ; then
        printf '\033[1;31;40m'
    fi
    printf -- "$1"
    if [ "$__INTERACTIVE" ] ; then
        printf '\033[0m'
    fi
}

__yellow(){
    if [ "$__INTERACTIVE" ] ; then
        printf '\033[1;31;33m'
    fi
    printf -- "$1"
    if [ "$__INTERACTIVE" ] ; then
        printf '\033[0m'
    fi
}

# Install IKEV2
function install_ikev2(){
    rootness
    get_system
    install_build_dependencies
    get_my_ip
    pre_install
    download_files
    setup_strongswan
    get_key
    configure_ipsec
    configure_strongswan
    configure_secrets
    SNAT_set
    iptables_check
    if command -v systemctl >/dev/null && [ -d /run/systemd/system ]; then
        systemctl daemon-reload
        systemctl enable strongswan-starter.service
        systemctl restart strongswan-starter.service
    else
        ipsec restart
    fi
    success_info
}

# Make sure only root can run our script
function rootness(){
if [[ $EUID -ne 0 ]]; then
   echo "Error:This script must be run as root!" 1>&2
   exit 1
fi
}

function detect_system(){
    local system_id=$1 system_like=$2 system_version=$3 major
    major=${system_version%%.*}
    if [[ ! "$major" =~ ^[0-9]+$ ]]; then
        return 1
    fi
    case "$system_id" in
        debian)
            (( 10#$major >= 12 )) || return 1
            system_str="1"
            ;;
        *)
            case " $system_id $system_like " in
                *" rhel "*|*" centos "*|*" rocky "*|*" almalinux "*|*" ol "*) ;;
                *) return 1 ;;
            esac
            (( 10#$major >= 8 )) || return 1
            system_str="0"
            ;;
    esac
}

function get_system(){
    local ID= ID_LIKE= VERSION_ID=
    if [ ! -r /etc/os-release ]; then
        echo "Cannot identify this operating system (/etc/os-release missing)." >&2
        exit 1
    fi
    . /etc/os-release
    if ! detect_system "$ID" "$ID_LIKE" "$VERSION_ID"; then
        echo "Unsupported operating system: ${ID:-unknown} ${VERSION_ID:-unknown}. Requires Debian 12+ or RHEL-compatible Linux 8+." >&2
        exit 1
    fi
}

#install necessary lib
function install_build_dependencies(){
    if [ "$system_str" = "0" ]; then
    dnf -y install pam-devel openssl-devel make gcc /usr/bin/curl tar openssl iproute iptables ca-certificates pkgconfig
    else
    apt-get -y update
    apt-get -y install libpam0g-dev libssl-dev make gcc curl tar openssl iproute2 iptables ca-certificates pkg-config
    fi
}

# Get IP address of the server
function get_my_ip(){
    echo "Preparing, Please wait a moment..."
    IP=$(curl -4fsS --max-time 10 https://api.ipify.org || true)
}

# Pre-installation settings
function pre_install(){
    echo "#############################################################"
    echo "# Install IKEv2 VPN for Debian 12+ or RHEL-compatible Linux 8+"
    echo "# Intro: https://quericy.me/blog/699"
    echo "#"
    echo "# Author:quericy"
    echo "#"
    echo "# Version:$VER"
    echo "#############################################################"
    echo "please choose the type of your VPS(Xen、KVM: 1  ,  OpenVZ: 2):"
    read -p "your choice(1 or 2):" os_choice
    if [ "$os_choice" = "1" ]; then
        os="1"
        os_str="Xen、KVM"
        else
            if [ "$os_choice" = "2" ]; then
                os="2"
                os_str="OpenVZ"
                else
                echo "wrong choice!"
                exit 1
            fi
    fi
    echo "please input the ip (or domain) of your VPS:"
    read -p "ip or domain(default_value:${IP}):" vps_ip
    if [ "$vps_ip" = "" ]; then
        vps_ip=$IP
    fi
    if [ -z "$vps_ip" ]; then
        echo "A server IP address or domain is required." >&2
        exit 1
    fi
    if [[ ! "$vps_ip" =~ ^[a-zA-Z0-9][a-zA-Z0-9.-]*$ ]]; then
        echo "Enter an IPv4 address or a domain name without wildcards." >&2
        exit 1
    fi

    echo "Would you want to import existing cert? You NEED copy your cert file to the same directory of this script"
    read -p "yes or no?(default_value:no):" have_cert
    if [ "$have_cert" = "yes" ]; then
        have_cert="1"
    else
        have_cert="0"
        echo "please input the cert country(C):"
        read -p "C(default value:US):" my_cert_c
        if [ "$my_cert_c" = "" ]; then
            my_cert_c="US"
        fi
        echo "please input the cert organization(O):"
        read -p "O(default value:myvpn):" my_cert_o
        if [ "$my_cert_o" = "" ]; then
            my_cert_o="myvpn"
        fi
        echo "please input the cert common name(CN):"
        read -p "CN(default value:VPN CA):" my_cert_cn
        if [ "$my_cert_cn" = "" ]; then
            my_cert_cn="VPN CA"
        fi
    fi

    echo "####################################"
    get_char(){
        SAVEDSTTY=`stty -g`
        stty -echo
        stty cbreak
        dd if=/dev/tty bs=1 count=1 2> /dev/null
        stty -raw
        stty echo
        stty $SAVEDSTTY
    }
    echo "Please confirm the information:"
    echo ""
    echo -e "the type of your server: [$(__green $os_str)]"
    echo -e "the ip(or domain) of your server: [$(__green $vps_ip)]"
    if [ "$have_cert" = "1" ]; then
        echo -e "$(__yellow "These are the certificate you MUST be prepared:")"
        echo -e "[$(__green "ca.cert.pem")]:The CA cert or the chain cert."
        echo -e "[$(__green "server.cert.pem")]:Your server cert."
        echo -e "[$(__green "server.pem")]:Your  key of the server cert."
        echo -e "[$(__yellow "Please copy these file to the same directory of this script before start!")]"
    else
        echo -e "the cert_info:[$(__green "C=${my_cert_c}, O=${my_cert_o}")]"
    fi
    echo ""
    echo "Press any key to start...or Press Ctrl+C to cancel"
    char=`get_char`
    #Current folder
    cur_dir=`pwd`
    cd "$cur_dir"
}


# Download strongswan
function download_files(){
    strongswan_version='strongswan-6.1.0'
    strongswan_file="$strongswan_version.tar.gz"
    if [ -f "$strongswan_file" ];then
        echo -e "$strongswan_file [$(__green "found")]"
    else
        if ! curl --fail --location --output "$strongswan_file.tmp" "https://download.strongswan.org/$strongswan_file";then
            echo "Failed to download $strongswan_file"
            exit 1
        fi
        mv "$strongswan_file.tmp" "$strongswan_file"
    fi
    tar xzf "$strongswan_file"
    if [ $? -eq 0 ];then
        cd "$cur_dir/$strongswan_version/"
    else
        echo ""
        echo "Unzip $strongswan_file failed! Please visit https://quericy.me/blog/699 and contact."
        exit 1
    fi
}

# configure and install strongswan
function setup_strongswan(){
    if [ "$os" = "1" ]; then
        ./configure --with-systemdsystemunitdir=/etc/systemd/system --enable-eap-identity --enable-eap-md5 \
--enable-eap-mschapv2 --enable-eap-tls --enable-eap-ttls --enable-eap-peap  \
--enable-eap-tnc --enable-eap-dynamic --enable-eap-radius --enable-xauth-eap  \
--enable-xauth-pam  --enable-dhcp  --enable-openssl  --enable-addrblock --enable-unity  \
--enable-certexpire --enable-radattr --enable-swanctl --enable-stroke --enable-ikev1 --enable-md4 --enable-des --disable-gmp || return 1

    else
        ./configure --with-systemdsystemunitdir=/etc/systemd/system --enable-eap-identity --enable-eap-md5 \
--enable-eap-mschapv2 --enable-eap-tls --enable-eap-ttls --enable-eap-peap  \
--enable-eap-tnc --enable-eap-dynamic --enable-eap-radius --enable-xauth-eap  \
--enable-xauth-pam  --enable-dhcp  --enable-openssl  --enable-addrblock --enable-unity  \
--enable-certexpire --enable-radattr --enable-swanctl --enable-stroke --enable-ikev1 --enable-md4 --enable-des --disable-gmp --enable-kernel-libipsec || return 1

    fi
    make && make install
}

# configure cert and key
function get_key(){
    cd "$cur_dir"
    if [ ! -d my_key ];then
        mkdir my_key
    fi
    if [ "$have_cert" = "1" ]; then
        import_cert
    else
        create_cert
    fi

    echo "####################################"
    get_char(){
        SAVEDSTTY=`stty -g`
        stty -echo
        stty cbreak
        dd if=/dev/tty bs=1 count=1 2> /dev/null
        stty -raw
        stty echo
        stty $SAVEDSTTY
    }
    cp -f ca.cert.pem /usr/local/etc/ipsec.d/cacerts/
    cp -f server.cert.pem /usr/local/etc/ipsec.d/certs/
    cp -f server.pem /usr/local/etc/ipsec.d/private/
    cp -f client.cert.pem /usr/local/etc/ipsec.d/certs/
    cp -f client.pem  /usr/local/etc/ipsec.d/private/
    echo "Cert copy completed"
}

# import cert if user has ssl certificate
function import_cert(){
    cd "$cur_dir"
   if [ -f ca.cert.pem ];then
        cp -f ca.cert.pem my_key/ca.cert.pem
        echo -e "ca.cert.pem [$(__green "found")]"
    else
        echo -e "ca.cert.pem [$(__red "Not found!")]"
        exit 1
    fi
    if [ -f server.cert.pem ];then
        cp -f server.cert.pem my_key/server.cert.pem
        cp -f server.cert.pem my_key/client.cert.pem
        echo -e "server.cert.pem [$(__green "found")]"
        echo -e "client.cert.pem [$(__green "auto create")]"
    else
        echo -e "server.cert.pem [$(__red "Not found!")]"
        exit 1
    fi
    if [ -f server.pem ];then
        cp -f server.pem my_key/server.pem
        cp -f server.pem my_key/client.pem
        echo -e "server.pem [$(__green "found")]"
        echo -e "client.pem [$(__green "auto create")]"
    else
        echo -e "server.pem [$(__red "Not found!")]"
        exit 1
    fi
    cd my_key
}

# auto create certificate
function create_cert(){
    cd "$cur_dir"
    cd my_key
    ipsec pki --gen --outform pem > ca.pem
    ipsec pki --self --in ca.pem --dn "C=${my_cert_c}, O=${my_cert_o}, CN=${my_cert_cn}" --ca --outform pem >ca.cert.pem
    ipsec pki --gen --outform pem > server.pem
    ipsec pki --pub --in server.pem | ipsec pki --issue --cacert ca.cert.pem \
    --cakey ca.pem --dn "C=${my_cert_c}, O=${my_cert_o}, CN=${vps_ip}" \
    --san="${vps_ip}" --flag serverAuth --flag ikeIntermediate \
    --outform pem > server.cert.pem
    ipsec pki --gen --outform pem > client.pem
    ipsec pki --pub --in client.pem | ipsec pki --issue --cacert ca.cert.pem --cakey ca.pem --dn "C=${my_cert_c}, O=${my_cert_o}, CN=VPN Client" --outform pem > client.cert.pem
    echo "configure the pkcs12 cert password(Can be empty):"
    openssl pkcs12 -export -inkey client.pem -in client.cert.pem -name "client" -certfile ca.cert.pem -caname "${my_cert_cn}"  -out client.cert.p12
}

# configure the ipsec.conf
function configure_ipsec(){
 cat > /usr/local/etc/ipsec.conf<<-EOF
config setup
    uniqueids=never 

conn iOS_cert
    keyexchange=ikev1
    fragmentation=yes
    left=%defaultroute
    leftauth=pubkey
    leftsubnet=0.0.0.0/0
    leftcert=server.cert.pem
    right=%any
    rightauth=pubkey
    rightauth2=xauth
    rightsourceip=10.31.2.0/24
    rightcert=client.cert.pem
    auto=add

conn android_xauth_psk
    keyexchange=ikev1
    left=%defaultroute
    leftauth=psk
    leftsubnet=0.0.0.0/0
    right=%any
    rightauth=psk
    rightauth2=xauth
    rightsourceip=10.31.2.0/24
    auto=add

conn networkmanager-strongswan
    keyexchange=ikev2
    left=%defaultroute
    leftauth=pubkey
    leftsubnet=0.0.0.0/0
    leftcert=server.cert.pem
    right=%any
    rightauth=pubkey
    rightsourceip=10.31.2.0/24
    rightcert=client.cert.pem
    auto=add

conn ios_ikev2
    keyexchange=ikev2
    rekey=no
    left=%defaultroute
    leftid=${vps_ip}
    leftsendcert=always
    leftsubnet=0.0.0.0/0
    leftcert=server.cert.pem
    right=%any
    rightauth=eap-mschapv2
    rightsourceip=10.31.2.0/24
    rightsendcert=never
    eap_identity=%any
    dpdaction=clear
    fragmentation=yes
    auto=add

EOF
}

# configure the strongswan.conf
function configure_strongswan(){
 if [ "$os" = "2" ]; then
    kernel_libipsec_load=10
 else
    kernel_libipsec_load=no
 fi
 cat > /usr/local/etc/strongswan.d/charon/kernel-libipsec.conf<<-EOF
kernel-libipsec {
    load = ${kernel_libipsec_load}
}
EOF
 cat > /usr/local/etc/strongswan.conf<<-EOF
 charon {
        load_modular = yes
        duplicheck {
                enable = no
        }
        compress = yes
        plugins {
                include strongswan.d/charon/*.conf
            attr {
                dns = 8.8.8.8, 8.8.4.4
            }
        }
}
include strongswan.d/*.conf
EOF
}

# configure the ipsec.secrets
function configure_secrets(){
    vpn_password=$(openssl rand -hex 16)
    vpn_psk=$(openssl rand -hex 24)
    vpn_xauth_password=$(openssl rand -hex 16)
    cat > /usr/local/etc/ipsec.secrets<<-EOF
: PKCS8 server.pem
: PSK "${vpn_psk}"
: XAUTH "${vpn_xauth_password}"
myUserName %any : EAP "${vpn_password}"
EOF
    chmod 600 /usr/local/etc/ipsec.secrets
}

function SNAT_set(){
    echo "Use SNAT could implove the speed,but your server MUST have static ip address."
    read -p "yes or no?(default_value:no):" use_SNAT
    if [ "$use_SNAT" = "yes" ]; then
        use_SNAT_str="1"
        echo -e "$(__yellow "ip address info:")"
        ip address | grep inet
        echo "Some servers has elastic IP (AWS) or mapping IP.In this case,you should input the IP address which is binding in network interface."
        read -p "static ip or network interface ip (default_value:${IP}):" static_ip
    if [ "$static_ip" = "" ]; then
        static_ip=$IP
    fi
    else
        use_SNAT_str="0"
    fi
}

# iptables check
function iptables_check(){
    cat > /etc/sysctl.d/10-ipsec.conf<<-EOF
net.ipv4.ip_forward=1
EOF
    sysctl --system
    echo "Do you use firewall in CentOS7 instead of iptables?"
    read -p "yes or no?(default_value:no):" use_firewall
    if [ "$use_firewall" = "yes" ]; then
        firewall_set
    else
        iptables_set
    fi
}

# firewall set in CentOS7
function firewall_set(){
    if ! systemctl is-active firewalld > /dev/null; then
        systemctl start firewalld
    fi
    firewall-cmd --permanent --add-service="ipsec"
    firewall-cmd --permanent --add-port=500/udp
    firewall-cmd --permanent --add-port=4500/udp
    firewall-cmd --permanent --add-masquerade
    firewall-cmd --reload
}

# iptables set
function iptables_set(){
    echo -e "$(__yellow "ip address info:")"
    ip address | grep inet
    echo "The above content is the network card information of your VPS."
    echo "[$(__yellow "Important")]Please enter the name of the interface which can be connected to the public network."
    default_interface=$(ip -4 route show default | awk 'NR == 1 {for (i = 1; i <= NF; i++) if ($i == "dev") {print $(i + 1); exit}}')
    if [ "$os" = "1" ]; then
            default_interface=${default_interface:-eth0}
            read -p "Network card interface(default_value:${default_interface}):" interface
        if [ "$interface" = "" ]; then
            interface="$default_interface"
        fi
        iptables -A FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT
        iptables -A FORWARD -s 10.31.0.0/24  -j ACCEPT
        iptables -A FORWARD -s 10.31.1.0/24  -j ACCEPT
        iptables -A FORWARD -s 10.31.2.0/24  -j ACCEPT
        iptables -A INPUT -i $interface -p esp -j ACCEPT
        iptables -A INPUT -i $interface -p udp --dport 500 -j ACCEPT
        iptables -A INPUT -i $interface -p tcp --dport 500 -j ACCEPT
        iptables -A INPUT -i $interface -p udp --dport 4500 -j ACCEPT
        iptables -A INPUT -i $interface -p udp --dport 1701 -j ACCEPT
        iptables -A INPUT -i $interface -p tcp --dport 1723 -j ACCEPT
        #iptables -A FORWARD -j REJECT
        if [ "$use_SNAT_str" = "1" ]; then
            iptables -t nat -A POSTROUTING -s 10.31.0.0/24 -o $interface -j SNAT --to-source $static_ip
            iptables -t nat -A POSTROUTING -s 10.31.1.0/24 -o $interface -j SNAT --to-source $static_ip
            iptables -t nat -A POSTROUTING -s 10.31.2.0/24 -o $interface -j SNAT --to-source $static_ip
        else
            iptables -t nat -A POSTROUTING -s 10.31.0.0/24 -o $interface -j MASQUERADE
            iptables -t nat -A POSTROUTING -s 10.31.1.0/24 -o $interface -j MASQUERADE
            iptables -t nat -A POSTROUTING -s 10.31.2.0/24 -o $interface -j MASQUERADE
        fi
    else
        default_interface=${default_interface:-venet0}
        read -p "Network card interface(default_value:${default_interface}):" interface
        if [ "$interface" = "" ]; then
            interface="$default_interface"
        fi
        iptables -A FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT
        iptables -A FORWARD -s 10.31.0.0/24  -j ACCEPT
        iptables -A FORWARD -s 10.31.1.0/24  -j ACCEPT
        iptables -A FORWARD -s 10.31.2.0/24  -j ACCEPT
        iptables -A INPUT -i $interface -p esp -j ACCEPT
        iptables -A INPUT -i $interface -p udp --dport 500 -j ACCEPT
        iptables -A INPUT -i $interface -p tcp --dport 500 -j ACCEPT
        iptables -A INPUT -i $interface -p udp --dport 4500 -j ACCEPT
        iptables -A INPUT -i $interface -p udp --dport 1701 -j ACCEPT
        iptables -A INPUT -i $interface -p tcp --dport 1723 -j ACCEPT
        #iptables -A FORWARD -j REJECT
        if [ "$use_SNAT_str" = "1" ]; then
            iptables -t nat -A POSTROUTING -s 10.31.0.0/24 -o $interface -j SNAT --to-source $static_ip
            iptables -t nat -A POSTROUTING -s 10.31.1.0/24 -o $interface -j SNAT --to-source $static_ip
            iptables -t nat -A POSTROUTING -s 10.31.2.0/24 -o $interface -j SNAT --to-source $static_ip
        else
            iptables -t nat -A POSTROUTING -s 10.31.0.0/24 -o $interface -j MASQUERADE
            iptables -t nat -A POSTROUTING -s 10.31.1.0/24 -o $interface -j MASQUERADE
            iptables -t nat -A POSTROUTING -s 10.31.2.0/24 -o $interface -j MASQUERADE
        fi
    fi
    iptables-save > /etc/iptables.rules
    if command -v systemctl >/dev/null && [ -d /run/systemd/system ]; then
        cat > /etc/systemd/system/ikev2-iptables.service<<-EOF
[Unit]
Description=Restore IKEv2 iptables rules
DefaultDependencies=no
Before=network-pre.target
Wants=network-pre.target

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'iptables-restore < /etc/iptables.rules'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        systemctl enable ikev2-iptables.service
    elif [ -d /etc/network/if-up.d ]; then
        cat > /etc/network/if-up.d/iptables<<-EOF
#!/bin/sh
iptables-restore < /etc/iptables.rules
EOF
        chmod +x /etc/network/if-up.d/iptables
    else
        echo "Could not configure automatic iptables restoration; restore /etc/iptables.rules at boot." >&2
    fi
}

# echo the success info
function success_info(){
    echo "#############################################################"
    echo -e "#"
    echo -e "# [$(__green "Install Complete")]"
    echo -e "# Version:$VER"
    echo -e "# There is the default login info of your IPSec/IkeV2 VPN Service"
    echo -e "# UserName:$(__green " myUserName")"
    echo -e "# PassWord:$(__green " ${vpn_password}")"
    echo -e "# XAUTH PassWord:$(__green " ${vpn_xauth_password}")"
    echo -e "# PSK:$(__green " ${vpn_psk}")"
    echo -e "# you should change default username and password in$(__green " /usr/local/etc/ipsec.secrets")"
    echo -e "# you cert:$(__green " ${cur_dir}/my_key/ca.cert.pem ")"
    if [ "$have_cert" = "1" ]; then
    echo -e "# you don't need to install cert if it's be trusted."
    else
    echo -e "# you must copy the cert to the client and install it."
    fi
    echo -e "#"
    echo -e "#############################################################"
    echo -e ""
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
    install_ikev2
fi
