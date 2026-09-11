#!/usr/bin/env bash
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH

#=================================================
#	System Required: CentOS/Debian/Ubuntu
#	Description: Shadowsocks Rust 管理脚本
#	Author: BFDZ
#	WebSite: https://slyw.me
#=================================================

sh_ver="1.5.0"
filepath=$(cd "$(dirname "$0")"; pwd)
file_1=$(echo -e "${filepath}"|awk -F "$0" '{print $1}')
FOLDER="/etc/ss-rust"
FILE="/usr/local/bin/ss-rust"
CONF="/etc/ss-rust/config.json"
Now_ver_File="/etc/ss-rust/ver.txt"
Local="/etc/sysctl.d/local.conf"

Green_font_prefix="\033[32m" && Red_font_prefix="\033[31m" && Green_background_prefix="\033[42;37m" && Red_background_prefix="\033[41;37m" && Font_color_suffix="\033[0m" && Yellow_font_prefix="\033[0;33m"
Info="${Green_font_prefix}[信息]${Font_color_suffix}"
Error="${Red_font_prefix}[错误]${Font_color_suffix}"
Tip="${Yellow_font_prefix}[注意]${Font_color_suffix}"

check_root(){
	[[ $EUID != 0 ]] && echo -e "${Error} 当前非ROOT账号(或没有ROOT权限)，无法继续操作，请更换ROOT账号或使用 ${Green_background_prefix}sudo su${Font_color_suffix} 命令获取临时ROOT权限（执行后可能会提示输入当前账号的密码）。" && exit 1
}

check_systemd(){
	command -v systemctl >/dev/null 2>&1 || { echo -e "${Error} 当前系统没有 systemd（systemctl），本脚本不支持！"; exit 1; }
}

check_sys(){
	local os_id="" os_like=""
	if [[ -f /etc/os-release ]]; then
		os_id=$(grep -E '^ID=' /etc/os-release | head -1 | cut -d= -f2 | tr -d '"')
		os_like=$(grep -E '^ID_LIKE=' /etc/os-release | head -1 | cut -d= -f2 | tr -d '"')
	elif [[ -f /etc/redhat-release ]]; then
		os_id="centos"
	elif grep -q -E -i "debian|ubuntu" /etc/issue 2>/dev/null; then
		os_id="debian"
	fi
	case "${os_id} ${os_like}" in
		*debian*|*ubuntu*)
			release="debian"
			;;
		*centos*|*rhel*|*fedora*|*rocky*|*almalinux*|*oracle*)
			release="centos"
			;;
		*opensuse*|*suse*|*sles*)
			release="suse"
			;;
		*arch*|*manjaro*)
			release="arch"
			;;
		*alpine*)
			release="alpine"
			;;
		*)
			release="unknown"
			;;
	esac
	if command -v dnf >/dev/null 2>&1; then
		pkg_mgr="dnf"
	elif command -v yum >/dev/null 2>&1; then
		pkg_mgr="yum"
	elif command -v apt-get >/dev/null 2>&1; then
		pkg_mgr="apt-get"
	elif command -v zypper >/dev/null 2>&1; then
		pkg_mgr="zypper"
	elif command -v pacman >/dev/null 2>&1; then
		pkg_mgr="pacman"
	elif command -v apk >/dev/null 2>&1; then
		pkg_mgr="apk"
	else
		pkg_mgr=""
	fi
}

sysArch() {
    uname=$(uname -m)
    arch_musl=""
    arch_gnu=""
    case "$uname" in
        x86_64|amd64)
            arch="x86_64"
            arch_musl="x86_64-unknown-linux-musl"
            arch_gnu="x86_64-unknown-linux-gnu"
            ;;
        i686|i386)
            arch="i686"
            arch_musl="i686-unknown-linux-musl"
            arch_gnu=""
            ;;
        aarch64|armv8*|arm64)
            arch="aarch64"
            arch_musl="aarch64-unknown-linux-musl"
            arch_gnu="aarch64-unknown-linux-gnu"
            ;;
        armv7*)
            arch="arm"
            arch_musl="armv7-unknown-linux-musleabihf"
            arch_gnu="armv7-unknown-linux-gnueabihf"
            ;;
        armv6*|arm)
            arch="arm"
            arch_musl="arm-unknown-linux-musleabihf"
            arch_gnu="arm-unknown-linux-gnueabihf"
            ;;
        mips64el)
            arch="mips64el"
            arch_musl=""
            arch_gnu="mips64el-unknown-linux-gnuabi64"
            ;;
        mipsel)
            arch="mipsel"
            arch_musl=""
            arch_gnu="mipsel-unknown-linux-gnu"
            ;;
        mips)
            arch="mips"
            arch_musl=""
            arch_gnu="mips-unknown-linux-gnu"
            ;;
        riscv64)
            arch="riscv64"
            arch_musl="riscv64gc-unknown-linux-musl"
            arch_gnu="riscv64gc-unknown-linux-gnu"
            ;;
        loongarch64)
            arch="loongarch64"
            arch_musl="loongarch64-unknown-linux-musl"
            arch_gnu="loongarch64-unknown-linux-gnu"
            ;;
        *)
            echo -e "${Error} 当前系统架构 [ ${uname} ] 不受官方预编译包支持！"
            echo -e "${Error} 请参考 https://github.com/shadowsocks/shadowsocks-rust/releases 自行编译安装。"
            exit 1
            ;;
    esac
}

#开启系统 TCP Fast Open
enable_systfo() {
	kernel=$(uname -r | awk -F . '{print $1}')
	if [ "$kernel" -ge 3 ]; then
		echo 3 >/proc/sys/net/ipv4/tcp_fastopen
		[[ ! -e $Local ]] && echo "fs.file-max = 51200
net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.core.rmem_default = 65536
net.core.wmem_default = 65536
net.core.netdev_max_backlog = 4096
net.core.somaxconn = 4096
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_tw_recycle = 0
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_keepalive_time = 1200
net.ipv4.ip_local_port_range = 10000 65000
net.ipv4.tcp_max_syn_backlog = 4096
net.ipv4.tcp_max_tw_buckets = 5000
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_rmem = 4096 87380 67108864
net.ipv4.tcp_wmem = 4096 65536 67108864
net.ipv4.tcp_mtu_probing = 1
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control = bbr" >>/etc/sysctl.d/local.conf && sysctl --system >/dev/null 2>&1
	else
		echo -e "$Error系统内核版本过低，无法支持 TCP Fast Open ！"
	fi
}

check_installed_status(){
	[[ ! -e ${FILE} ]] && echo -e "${Error} Shadowsocks Rust 没有安装，请检查！" && exit 1
}

check_status(){
	status="$(systemctl is-active ss-rust 2>/dev/null)"
	[[ "${status}" == "active" ]] && status="running"
	return 0
}

check_new_ver(){
	if ! command -v jq >/dev/null 2>&1; then
		echo -e "${Error} 缺少 jq，无法解析版本信息，请先安装 jq！"
		return 1
	fi
	new_ver=$(wget -qO- --timeout=10 https://api.github.com/repos/shadowsocks/shadowsocks-rust/releases | jq -r '[.[] | select(.prerelease == false) | select(.draft == false) | .tag_name] | .[0]' 2>/dev/null)
	if [[ -z "${new_ver}" || "${new_ver}" == "null" ]]; then
		echo -e "${Tip} GitHub API 获取失败，尝试备用方式获取版本……"
		new_ver=$(wget -qO- --no-check-certificate --timeout=10 "https://github.com/shadowsocks/shadowsocks-rust/releases/latest" | grep -oE 'releases/tag/v[0-9]+\.[0-9]+\.[0-9]+' | head -1 | awk -F/ '{print $NF}')
	fi
	if [[ -z "${new_ver}" ]]; then
		echo -e "${Error} Shadowsocks Rust 最新版本获取失败！"
		return 1
	fi
	echo -e "${Info} 检测到 Shadowsocks Rust 最新版本为 [ ${new_ver} ]"
	return 0
}

check_ver_comparison(){
	now_ver=$(cat ${Now_ver_File})
	if [[ "${now_ver}" != "${new_ver}" ]]; then
		echo -e "${Info} 发现 Shadowsocks Rust 已有新版本 [ ${new_ver} ]，旧版本 [ ${now_ver} ]"
		read -e -p "是否更新 ？ [Y/n]：" yn
		[[ -z "${yn}" ]] && yn="y"
		if [[ $yn == [Yy] ]]; then
			check_status
			# [[ "$status" == "running" ]] && systemctl stop ss-rust
			\cp "${CONF}" "/tmp/config.json"
			# rm -rf ${FOLDER}
			Download
			mv -f "/tmp/config.json" "${CONF}"
			Restart
		fi
	else
		echo -e "${Info} 当前 Shadowsocks Rust 已是最新版本 [ ${new_ver} ] ！" && exit 1
	fi
}

# Download(){
# 	if [[ ! -e "${FOLDER}" ]]; then
# 		mkdir "${FOLDER}"
# 	# else
# 		# [[ -e "${FILE}" ]] && rm -rf "${FILE}"
# 	fi
# 	echo -e "${Info} 开始下载 Shadowsocks Rust ……"
# 	wget --no-check-certificate -N "https://github.com/shadowsocks/shadowsocks-rust/releases/download/${new_ver}/shadowsocks-${new_ver}.${arch}-unknown-linux-gnu.tar.xz"
# 	[[ ! -e "shadowsocks-${new_ver}.${arch}-unknown-linux-gnu.tar.xz" ]] && echo -e "${Error} Shadowsocks Rust 下载失败！" && exit 1
# 	tar -xvf "shadowsocks-${new_ver}.${arch}-unknown-linux-gnu.tar.xz"
# 	[[ ! -e "ssserver" ]] && echo -e "${Error} Shadowsocks Rust 压缩包解压失败！" && exit 1
# 	rm -rf "shadowsocks-${new_ver}.${arch}-unknown-linux-gnu.tar.xz"
# 	chmod +x ssserver
# 	mv -f ssserver "${FILE}"
# 	rm sslocal ssmanager ssservice ssurl
# 	echo "${new_ver}" > ${Now_ver_File}
#     echo -e "${Info} Shadowsocks Rust 主程序下载安装完毕！"
# }

# 官方源
stable_Download() {
	echo -e "${Info} 开始下载官方源 Shadowsocks Rust ……"
	local tar_file="" target=""
	if [[ -n "${arch_musl}" ]]; then
		target="${arch_musl}"
		tar_file="shadowsocks-${new_ver}.${target}.tar.xz"
		echo -e "${Info} 优先下载 musl 静态链接版本 (${target})，兼容低版本 glibc 系统……"
		wget --no-check-certificate -N "https://github.com/shadowsocks/shadowsocks-rust/releases/download/${new_ver}/${tar_file}"
	fi
	if [[ -z "${tar_file}" || ! -e "${tar_file}" ]] && [[ -n "${arch_gnu}" ]]; then
		target="${arch_gnu}"
		tar_file="shadowsocks-${new_ver}.${target}.tar.xz"
		echo -e "${Tip} musl 版本不可用，尝试下载 gnu 版本 (${target})……"
		wget --no-check-certificate -N "https://github.com/shadowsocks/shadowsocks-rust/releases/download/${new_ver}/${tar_file}"
	fi
	if [[ -z "${tar_file}" || ! -e "${tar_file}" ]]; then
		echo -e "${Error} Shadowsocks Rust 官方源下载失败！"
		return 1 && exit 1
	else
		tar -xvf "${tar_file}"
	fi
	if [[ ! -e "ssserver" ]]; then
		echo -e "${Error} Shadowsocks Rust 解压失败！"
		echo -e "${Error} Shadowsocks Rust 安装失败 !"
		return 1 && exit 1
	else
		rm -rf "${tar_file}"
		chmod +x ssserver
		mv -f ssserver "${FILE}"
		rm sslocal ssmanager ssservice ssurl
		echo "${new_ver}" > ${Now_ver_File}

		echo -e "${Info} Shadowsocks Rust 主程序下载安装完毕！"
		return 0
	fi
}

# 备用源
backup_Download() {
	echo -e "${Info} 试图请求 备份源(旧版本) Shadowsocks Rust ……"
	wget --no-check-certificate -N "https://raw.githubusercontent.com/xOS/Others/master/shadowsocks-rust/v1.14.1/shadowsocks-v1.14.1.${arch}-unknown-linux-gnu.tar.xz"
	if [[ ! -e "shadowsocks-v1.14.1.${arch}-unknown-linux-gnu.tar.xz" ]]; then
		echo -e "${Error} Shadowsocks Rust 备份源(旧版本) 下载失败！"
		return 1 && exit 1
	else
		tar -xvf "shadowsocks-v1.14.1.${arch}-unknown-linux-gnu.tar.xz"
	fi
	if [[ ! -e "ssserver" ]]; then
		echo -e "${Error} Shadowsocks Rust 备份源(旧版本) 解压失败 !"
		echo -e "${Error} Shadowsocks Rust 备份源(旧版本) 安装失败 !"
		return 1 && exit 1
	else
		rm -rf "shadowsocks-v1.14.1.${arch}-unknown-linux-gnu.tar.xz"
		chmod +x ssserver
	    mv -f ssserver "${FILE}"
	    rm sslocal ssmanager ssservice ssurl
		echo "v1.14.1" > ${Now_ver_File}
		echo -e "${Info} Shadowsocks Rust 备份源(旧版本) 主程序下载安装完毕！"
		return 0
	fi
}

Download() {
	if [[ ! -e "${FOLDER}" ]]; then
		mkdir "${FOLDER}"
	# else
		# [[ -e "${FILE}" ]] && rm -rf "${FILE}"
	fi
	stable_Download
	if [[ $? != 0 ]]; then
		backup_Download
	fi
}

Service(){
	echo '
[Unit]
Description= Shadowsocks Rust Service
After=network-online.target
Wants=network-online.target systemd-networkd-wait-online.service
[Service]
LimitNOFILE=32767 
Type=simple
User=root
Restart=on-failure
RestartSec=5s
DynamicUser=true
ExecStartPre=/bin/sh -c 'ulimit -n 51200'
ExecStart=/usr/local/bin/ss-rust -c /etc/ss-rust/config.json
[Install]
WantedBy=multi-user.target' > /etc/systemd/system/ss-rust.service
	systemctl daemon-reload
	systemctl enable ss-rust
	echo -e "${Info} Shadowsocks Rust 服务配置完成！"
}

Installation_dependency(){
	case "${pkg_mgr}" in
		dnf|yum)
			${pkg_mgr} install -y jq gzip wget curl unzip xz
			;;
		apt-get)
			apt-get update && apt-get install -y jq gzip wget curl unzip xz-utils
			;;
		zypper)
			zypper --non-interactive --gpg-auto-import-keys install jq gzip wget curl unzip xz
			;;
		pacman)
			pacman -Sy --noconfirm --needed jq gzip wget curl unzip xz
			;;
		apk)
			apk add --no-cache jq gzip wget curl unzip xz
			;;
		*)
			echo -e "${Error} 未识别的包管理器，请手动安装依赖：jq gzip wget curl unzip xz"
			;;
	esac
	[[ -f /usr/share/zoneinfo/Asia/Shanghai ]] && \cp -f /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
}

Write_config(){
	cat > ${CONF}<<-EOF
{
    "server": "::",
    "server_port": ${port},
    "password": "${password}",
    "method": "${cipher}",
    "fast_open": ${tfo},
    "mode": "tcp_and_udp",
    "user":"nobody",
    "timeout":300,
    "nameserver":"8.8.8.8"
}
EOF
}

Read_config(){
	[[ ! -e ${CONF} ]] && echo -e "${Error} Shadowsocks Rust 配置文件不存在！" && exit 1
	port=$(cat ${CONF}|jq -r '.server_port')
	password=$(cat ${CONF}|jq -r '.password')
	cipher=$(cat ${CONF}|jq -r '.method')
	tfo=$(cat ${CONF}|jq -r '.fast_open')
}

Set_port(){
	while true
		do
		echo -e "${Tip} 本步骤不涉及系统防火墙端口操作，请手动放行相应端口！"
		echo -e "请输入 Shadowsocks Rust 端口 [1-65535]"
		read -e -p "(默认：2525)：" port
		[[ -z "${port}" ]] && port="2525"
		echo $((${port}+0)) &>/dev/null
		if [[ $? -eq 0 ]]; then
			if [[ ${port} -ge 1 ]] && [[ ${port} -le 65535 ]]; then
				echo && echo "=================================="
				echo -e "端口：${Red_background_prefix} ${port} ${Font_color_suffix}"
				echo "==================================" && echo
				break
			else
				echo "输入错误, 请输入正确的端口。"
			fi
		else
			echo "输入错误, 请输入正确的端口。"
		fi
		done
}

Set_tfo(){
	echo -e "是否开启 TCP Fast Open ？
==================================
${Green_font_prefix} 1.${Font_color_suffix} 开启  ${Green_font_prefix} 2.${Font_color_suffix} 关闭
=================================="
	read -e -p "(默认：1.开启)：" tfo
	[[ -z "${tfo}" ]] && tfo="1"
	if [[ ${tfo} == "1" ]]; then
		tfo=true
		enable_systfo
	else
		tfo=false
	fi
	echo && echo "=================================="
	echo -e "TCP Fast Open 开启状态：${Red_background_prefix} ${tfo} ${Font_color_suffix}"
	echo "==================================" && echo
}

Gen_psk(){
	local bytes=32
	[[ "$1" == "2022-blake3-aes-128-gcm" ]] && bytes=16
	if command -v openssl >/dev/null 2>&1; then
		openssl rand -base64 "${bytes}"
	else
		head -c "${bytes}" /dev/urandom | base64 | tr -d '\n'
	fi
}

check_psk(){
	local need=""
	case "$2" in
		2022-blake3-aes-128-gcm) need=16 ;;
		2022-blake3-aes-256-gcm|2022-blake3-chacha20-poly1305) need=32 ;;
		*) return 0 ;;
	esac
	local len
	len=$(printf '%s' "$1" | base64 -d 2>/dev/null | wc -c)
	[[ "${len}" == "${need}" ]]
}

Set_password(){
	echo "请输入 Shadowsocks Rust 密码"
	if [[ "${cipher}" == 2022-blake3-* ]]; then
		local keylen="32"
		[[ "${cipher}" == "2022-blake3-aes-128-gcm" ]] && keylen="16"
		read -e -p "(默认：随机生成${keylen}字节 base64 密钥)：" password
		if [[ -z "${password}" ]]; then
			password=$(Gen_psk "${cipher}")
		elif ! check_psk "${password}" "${cipher}"; then
			echo -e "${Tip} 当前密码不是 ${keylen} 字节的合法 base64 密钥，${cipher} 可能启动失败！"
		fi
	else
		read -e -p "(默认：随机生成32位长度)：" password
		[[ -z "${password}" ]] && password=$(Gen_psk "${cipher}")
	fi
	echo && echo "=================================="
	echo -e "密码：${Red_background_prefix} ${password} ${Font_color_suffix}"
	echo "==================================" && echo
}

Set_cipher(){
	echo -e "请选择 Shadowsocks Rust 加密方式
==================================	
 ${Green_font_prefix} 1.${Font_color_suffix} 2022-blake3-chacha20-poly1305 ${Green_font_prefix}(默认)${Font_color_suffix}
 ${Green_font_prefix} 2.${Font_color_suffix} 2022-blake3-aes-128-gcm ${Green_font_prefix}(推荐)${Font_color_suffix}
 ${Green_font_prefix} 3.${Font_color_suffix} 2022-blake3-aes-256-gcm ${Green_font_prefix}(推荐)${Font_color_suffix}
 ${Green_font_prefix} 4.${Font_color_suffix} plain ${Red_font_prefix}(不推荐)${Font_color_suffix}
 ${Green_font_prefix} 5.${Font_color_suffix} none ${Red_font_prefix}(不推荐)${Font_color_suffix}
 ${Green_font_prefix} 6.${Font_color_suffix} table
 ${Green_font_prefix} 7.${Font_color_suffix} aes-128-cfb
 ${Green_font_prefix} 8.${Font_color_suffix} aes-256-cfb
 ${Green_font_prefix} 9.${Font_color_suffix} aes-256-ctr 
 ${Green_font_prefix}10.${Font_color_suffix} camellia-256-cfb
 ${Green_font_prefix}11.${Font_color_suffix} rc4-md5
 ${Green_font_prefix}12.${Font_color_suffix} chacha20-ietf
==================================
 ${Tip} 如需其它加密方式请手动修改配置文件 !" && echo
	read -e -p "(默认: 1. 2022-blake3-chacha20-poly1305)：" cipher
	[[ -z "${cipher}" ]] && cipher="1"
	if [[ ${cipher} == "1" ]]; then
		cipher="2022-blake3-chacha20-poly1305"
	elif [[ ${cipher} == "2" ]]; then
		cipher="2022-blake3-aes-128-gcm"
	elif [[ ${cipher} == "3" ]]; then
		cipher="2022-blake3-aes-256-gcm"
	elif [[ ${cipher} == "4" ]]; then
		cipher="plain"
	elif [[ ${cipher} == "5" ]]; then
		cipher="none"
	elif [[ ${cipher} == "6" ]]; then
		cipher="table"
	elif [[ ${cipher} == "7" ]]; then
		cipher="aes-128-cfb"
	elif [[ ${cipher} == "8" ]]; then
		cipher="aes-256-cfb"
	elif [[ ${cipher} == "9" ]]; then
		cipher="aes-256-ctr"
	elif [[ ${cipher} == "10" ]]; then
		cipher="camellia-256-cfb"
	elif [[ ${cipher} == "11" ]]; then
		cipher="rc4-md5"
	elif [[ ${cipher} == "12" ]]; then
		cipher="chacha20-ietf"
	else
		cipher="aes-256-gcm"
	fi
	echo && echo "=================================="
	echo -e "加密：${Red_background_prefix} ${cipher} ${Font_color_suffix}"
	echo "==================================" && echo
}

Set(){
	check_installed_status
	echo && echo -e "你要做什么？
==================================
 ${Green_font_prefix}1.${Font_color_suffix}  修改 端口配置
 ${Green_font_prefix}2.${Font_color_suffix}  修改 密码配置
 ${Green_font_prefix}3.${Font_color_suffix}  修改 加密配置
 ${Green_font_prefix}4.${Font_color_suffix}  修改 TFO 配置
==================================
 ${Green_font_prefix}5.${Font_color_suffix}  修改 全部配置" && echo
	read -e -p "(默认：取消)：" modify
	[[ -z "${modify}" ]] && echo "已取消..." && exit 1
	if [[ "${modify}" == "1" ]]; then
		Read_config
		Set_port
		password=${password}
		cipher=${cipher}
		tfo=${tfo}
		Write_config
		Restart
	elif [[ "${modify}" == "2" ]]; then
		Read_config
		Set_password
		port=${port}
		cipher=${cipher}
		tfo=${tfo}
		Write_config
		Restart
	elif [[ "${modify}" == "3" ]]; then
		Read_config
		Set_cipher
		if [[ "${cipher}" == 2022-blake3-* ]] && ! check_psk "${password}" "${cipher}"; then
			echo -e "${Tip} 原密码不适用于当前 2022 加密，已自动重新生成密钥"
			password=$(Gen_psk "${cipher}")
		fi
		port=${port}
		password=${password}
		tfo=${tfo}
		Write_config
		Restart
	elif [[ "${modify}" == "4" ]]; then
		Read_config
		Set_tfo
		cipher=${cipher}
		port=${port}
		password=${password}
		Write_config
		Restart
	elif [[ "${modify}" == "5" ]]; then
		Read_config
		Set_port
		Set_cipher
		Set_password
		Set_tfo
		Write_config
		Restart
	else
		echo -e "${Error} 请输入正确的数字(1-5)" && exit 1
	fi
}

Install(){
	[[ -e ${FILE} ]] && echo -e "${Error} 检测到 Shadowsocks Rust 已安装！" && exit 1
	echo -e "${Info} 开始设置 配置..."
	Set_port
	Set_cipher
	Set_password
	Set_tfo
	echo -e "${Info} 开始安装/配置 依赖..."
	Installation_dependency
	echo -e "${Info} 开始下载/安装..."
	check_new_ver || exit 1
	Download
	echo -e "${Info} 开始写入 配置文件..."
	Write_config
	echo -e "${Info} 开始安装系统服务脚本..."
	Service
	echo -e "${Info} 所有步骤 安装完毕，开始启动..."
	Start
}

Start(){
	check_installed_status
	check_status
	[[ "$status" == "running" ]] && echo -e "${Info} Shadowsocks Rust 已在运行 ！" && exit 1
	systemctl start ss-rust
	check_status
	[[ "$status" == "running" ]] && echo -e "${Info} Shadowsocks Rust 启动成功 ！"
    sleep 3s
    Start_Menu
}

Stop(){
	check_installed_status
	check_status
	[[ "$status" != "running" ]] && echo -e "${Error} Shadowsocks Rust 没有运行，请检查！" && exit 1
	systemctl stop ss-rust
    sleep 3s
    Start_Menu
}

Restart(){
	check_installed_status
	systemctl restart ss-rust
	echo -e "${Info} Shadowsocks Rust 重启完毕 ！"
	sleep 3s
	View
    Start_Menu
}

Update(){
	check_installed_status
	check_new_ver || exit 1
	check_ver_comparison
	echo -e "${Info} Shadowsocks Rust 更新完毕！"
    sleep 3s
    Start_Menu
}

Uninstall(){
	check_installed_status
	echo "确定要卸载 Shadowsocks Rust ? (y/N)"
	echo
	read -e -p "(默认：n)：" unyn
	[[ -z ${unyn} ]] && unyn="n"
	if [[ ${unyn} == [Yy] ]]; then
		check_status
		[[ "$status" == "running" ]] && systemctl stop ss-rust
		systemctl disable ss-rust 2>/dev/null
		rm -f /etc/systemd/system/ss-rust.service
		systemctl daemon-reload
		systemctl reset-failed ss-rust 2>/dev/null
		rm -rf "${FOLDER}"
		rm -rf "${FILE}"
		echo && echo "Shadowsocks Rust 卸载完成！" && echo
	else
		echo && echo "卸载已取消..." && echo
	fi
    sleep 3s
    Start_Menu
}

getipv4(){
	ipv4=$(wget -qO- -4 -t1 -T2 ipinfo.io/ip)
	if [[ -z "${ipv4}" ]]; then
		ipv4=$(wget -qO- -4 -t1 -T2 api.ip.sb/ip)
		if [[ -z "${ipv4}" ]]; then
			ipv4=$(wget -qO- -4 -t1 -T2 members.3322.org/dyndns/getip)
			if [[ -z "${ipv4}" ]]; then
				ipv4="IPv4_Error"
			fi
		fi
	fi
}
getipv6(){
	ipv6=$(wget -qO- -6 -t1 -T2 ifconfig.co)
	if [[ -z "${ipv6}" ]]; then
		ipv6="IPv6_Error"
	fi
}

urlsafe_base64(){
	date=$(echo -n "$1"|base64|sed ':a;N;s/\n/ /g;ta'|sed 's/ //g;s/=//g;s/+/-/g;s/\//_/g')
	echo -e "${date}"
}

Gen_QR(){
	if command -v qrencode >/dev/null 2>&1; then
		qrencode -t ANSIUTF8 "$1"
	else
		echo -e " 二维码：未安装 qrencode，无法本地生成（可安装 qrencode 后查看，或使用上方 ss:// 链接）"
	fi
}

Link_QR(){
	if [[ "${ipv4}" != "IPv4_Error" ]]; then
		SSbase64=$(urlsafe_base64 "${cipher}:${password}@${ipv4}:${port}")
		SSurl="ss://${SSbase64}"
		link_ipv4=" 链接  [IPv4]：${Red_font_prefix}${SSurl}${Font_color_suffix}
$(Gen_QR "${SSurl}")"
	fi
	if [[ "${ipv6}" != "IPv6_Error" ]]; then
		SSbase64=$(urlsafe_base64 "${cipher}:${password}@${ipv6}:${port}")
		SSurl="ss://${SSbase64}"
		link_ipv6=" 链接  [IPv6]：${Red_font_prefix}${SSurl}${Font_color_suffix}
$(Gen_QR "${SSurl}")"
	fi
}

View(){
	check_installed_status
	Read_config
	getipv4
	getipv6
	Link_QR
	clear && echo
	echo -e "Shadowsocks Rust 配置："
	echo -e "——————————————————————————————————"
	[[ "${ipv4}" != "IPv4_Error" ]] && echo -e " 地址：${Green_font_prefix}${ipv4}${Font_color_suffix}"
	[[ "${ipv6}" != "IPv6_Error" ]] && echo -e " 地址：${Green_font_prefix}${ipv6}${Font_color_suffix}"
	echo -e " 端口：${Green_font_prefix}${port}${Font_color_suffix}"
	echo -e " 密码：${Green_font_prefix}${password}${Font_color_suffix}"
	echo -e " 加密：${Green_font_prefix}${cipher}${Font_color_suffix}"
	echo -e " TFO ：${Green_font_prefix}${tfo}${Font_color_suffix}"
	echo -e "——————————————————————————————————"
	[[ ! -z "${link_ipv4}" ]] && echo -e "${link_ipv4}"
	[[ ! -z "${link_ipv6}" ]] && echo -e "${link_ipv6}"
	echo -e "——————————————————————————————————"
	Before_Start_Menu
}

Status(){
	echo -e "${Info} 获取 Shadowsocks Rust 活动日志 ……"
	echo -e "${Tip} 返回主菜单请按 q ！"
	systemctl status ss-rust
	Start_Menu
}

Update_Shell(){
	local sh_url="https://raw.githubusercontent.com/BFDZ/Shadowsocks-Rust/master/ss-rust.sh"
	echo -e "当前版本为 [ ${sh_ver} ]，开始检测最新版本..."
	sh_new_ver=$(wget --no-check-certificate -qO- "${sh_url}"|grep 'sh_ver="'|awk -F "=" '{print $NF}'|sed 's/\"//g'|head -1)
	if [[ -z "${sh_new_ver}" ]]; then
		echo -e "${Error} 检测最新版本失败 !"
		sleep 3s
		Start_Menu
		return 0
	fi
	if [[ "${sh_new_ver}" != "${sh_ver}" ]]; then
		echo -e "发现新版本[ ${sh_new_ver} ]，是否更新？[Y/n]"
		read -p "(默认：y)：" yn
		[[ -z "${yn}" ]] && yn="y"
		if [[ ${yn} == [Yy] ]]; then
			if wget -O "${filepath}/ss-rust.sh" --no-check-certificate "${sh_url}"; then
				chmod +x "${filepath}/ss-rust.sh"
				echo -e "脚本已更新为最新版本[ ${sh_new_ver} ]！"
				echo -e "3s后执行新脚本"
				sleep 3s
				bash "${filepath}/ss-rust.sh"
			else
				echo -e "${Error} 脚本更新失败，请检查网络 !"
				sleep 3s
				Start_Menu
			fi
		else
			echo && echo "	已取消..." && echo
			sleep 3s
			Start_Menu
		fi
	else
		echo -e "当前已是最新版本[ ${sh_new_ver} ] ！"
		sleep 3s
		Start_Menu
	fi
}

Before_Start_Menu() {
    echo && echo -n -e "${Yellow_font_prefix}* 按回车返回主菜单 *${Font_color_suffix}" && read temp
    Start_Menu
}

Start_Menu(){
clear
check_root
check_systemd
check_sys
sysArch
action=$1
	echo && echo -e "  
==================================
Shadowsocks Rust 管理脚本 ${Red_font_prefix}[v${sh_ver}]${Font_color_suffix}
==================================
 ${Green_font_prefix} 0.${Font_color_suffix} 更新脚本
——————————————————————————————————
 ${Green_font_prefix} 1.${Font_color_suffix} 安装 Shadowsocks Rust
 ${Green_font_prefix} 2.${Font_color_suffix} 更新 Shadowsocks Rust
 ${Green_font_prefix} 3.${Font_color_suffix} 卸载 Shadowsocks Rust
——————————————————————————————————
 ${Green_font_prefix} 4.${Font_color_suffix} 启动 Shadowsocks Rust
 ${Green_font_prefix} 5.${Font_color_suffix} 停止 Shadowsocks Rust
 ${Green_font_prefix} 6.${Font_color_suffix} 重启 Shadowsocks Rust
——————————————————————————————————
 ${Green_font_prefix} 7.${Font_color_suffix} 设置 配置信息
 ${Green_font_prefix} 8.${Font_color_suffix} 查看 配置信息
 ${Green_font_prefix} 9.${Font_color_suffix} 查看 运行状态
——————————————————————————————————
 ${Green_font_prefix} 10.${Font_color_suffix} 退出脚本
==================================" && echo
	if [[ -e ${FILE} ]]; then
		check_status
		if [[ "$status" == "running" ]]; then
			echo -e " 当前状态：${Green_font_prefix}已安装${Font_color_suffix} 并 ${Green_font_prefix}已启动${Font_color_suffix}"
		else
			echo -e " 当前状态：${Green_font_prefix}已安装${Font_color_suffix} 但 ${Red_font_prefix}未启动${Font_color_suffix}"
		fi
	else
		echo -e " 当前状态：${Red_font_prefix}未安装${Font_color_suffix}"
	fi
	echo
	read -e -p " 请输入数字 [0-10]：" num
	case "$num" in
		0)
		Update_Shell
		;;
		1)
		Install
		;;
		2)
		Update
		;;
		3)
		Uninstall
		;;
		4)
		Start
		;;
		5)
		Stop
		;;
		6)
		Restart
		;;
		7)
		Set
		;;
		8)
		View
		;;
		9)
		Status
		;;
		10)
		exit 1
		;;
		*)
		echo "请输入正确数字 [0-10]"
		;;
	esac
}
Start_Menu
