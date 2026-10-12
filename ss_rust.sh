#!/usr/bin/env bash
# STREAMING_CHUNK:Configuring script environments and constants...
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH

#=================================================
#	System Required: Alpine/CentOS/Debian/Ubuntu
#	Description: Shadowsocks Rust 管理脚本 (支持 Systemd 与 OpenRC)
#	Author: BFDZ
#	WebSite: https://slyw.me
#=================================================

sh_ver="1.6.0"
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

# STREAMING_CHUNK:Defining system environment check functions...
check_root(){
	[[ $EUID != 0 ]] && echo -e "${Error} 当前非ROOT账号(或没有ROOT权限)，无法继续操作，请更换ROOT账号或使用 ${Green_background_prefix}sudo su${Font_color_suffix} 命令获取临时ROOT权限。" && exit 1
}

check_init(){
	if command -v systemctl >/dev/null 2>&1 && [[ -d /run/systemd/system ]]; then
		init_sys="systemd"
	elif command -v rc-service >/dev/null 2>&1 && [[ -d /etc/init.d ]]; then
		init_sys="openrc"
	elif command -v systemctl >/dev/null 2>&1; then
		init_sys="systemd"
	elif [[ -d /etc/init.d ]] && command -v rc-update >/dev/null 2>&1; then
		init_sys="openrc"
	else
		echo -e "${Error} 未检测到 systemd 或 OpenRC，本脚本暂不支持当前系统的服务管理！"
		exit 1
	fi
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
		*alpine*)
			release="alpine"
			;;
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
		*)
			release="unknown"
			;;
	esac
	if command -v apk >/dev/null 2>&1; then
		pkg_mgr="apk"
	elif command -v apt-get >/dev/null 2>&1; then
		pkg_mgr="apt-get"
	elif command -v dnf >/dev/null 2>&1; then
		pkg_mgr="dnf"
	elif command -v yum >/dev/null 2>&1; then
		pkg_mgr="yum"
	elif command -v zypper >/dev/null 2>&1; then
		pkg_mgr="zypper"
	elif command -v pacman >/dev/null 2>&1; then
		pkg_mgr="pacman"
	else
		pkg_mgr=""
	fi
}

# STREAMING_CHUNK:Detecting system architecture...
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

# STREAMING_CHUNK:Configuring system TCP Fast Open and network parameters...
enable_systfo() {
	kernel=$(uname -r | awk -F . '{print $1}')
	if [ "$kernel" -ge 3 ]; then
		echo 3 >/proc/sys/net/ipv4/tcp_fastopen 2>/dev/null
		mkdir -p /etc/sysctl.d
		if [[ ! -e $Local ]]; then
			cat > "$Local" <<-EOF
fs.file-max = 51200
net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.core.rmem_default = 65536
net.core.wmem_default = 65536
net.core.netdev_max_backlog = 4096
net.core.somaxconn = 4096
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_tw_reuse = 1
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
net.ipv4.tcp_congestion_control = bbr
EOF
		fi
		# 适配 Alpine/Busybox 与普通 systemd 系统的 sysctl 生效方式
		if command -v sysctl >/dev/null 2>&1; then
			sysctl -p "$Local" >/dev/null 2>&1 || sysctl --system >/dev/null 2>&1 || sysctl -p >/dev/null 2>&1
		fi
	else
		echo -e "${Error} 系统内核版本过低，无法支持 TCP Fast Open ！"
	fi
}

check_installed_status(){
	[[ ! -e ${FILE} ]] && echo -e "${Error} Shadowsocks Rust 没有安装，请检查！" && exit 1
}

# STREAMING_CHUNK:Handling service status checks...
check_status(){
	status="stopped"
	case "${init_sys}" in
		systemd)
			local s_active
			s_active="$(systemctl is-active ss-rust 2>/dev/null)"
			[[ "${s_active}" == "active" ]] && status="running"
			;;
		openrc)
			if rc-service ss-rust status >/dev/null 2>&1; then
				status="running"
			elif pgrep -f "${FILE}" >/dev/null 2>&1; then
				status="running"
			else
				status="stopped"
			fi
			;;
		*)
			if pgrep -f "${FILE}" >/dev/null 2>&1; then
				status="running"
			else
				status="stopped"
			fi
			;;
	esac
	return 0
}

# STREAMING_CHUNK:Checking remote version details...
check_new_ver(){
	echo -e "${Info} 正在检测 Shadowsocks Rust 最新版本..."
	new_ver=""
	if command -v curl >/dev/null 2>&1; then
		# 优先尝试 GitHub redirect tag (避免 API 限频)
		new_ver=$(curl -sSLI -o /dev/null -w %{url_effective} --connect-timeout 8 "https://github.com/shadowsocks/shadowsocks-rust/releases/latest" 2>/dev/null | awk -F'/' '{print $NF}')
	fi

	if [[ -z "${new_ver}" || "${new_ver}" == "latest" ]]; then
		if command -v jq >/dev/null 2>&1; then
			new_ver=$(wget -qO- --timeout=8 https://api.github.com/repos/shadowsocks/shadowsocks-rust/releases | jq -r '[.[] | select(.prerelease == false) | select(.draft == false) | .tag_name] | .[0]' 2>/dev/null)
		fi
	fi

	if [[ -z "${new_ver}" || "${new_ver}" == "null" ]]; then
		new_ver=$(wget -qO- --no-check-certificate --timeout=8 "https://github.com/shadowsocks/shadowsocks-rust/releases" 2>/dev/null | grep -oE '/releases/tag/v[0-9]+\.[0-9]+\.[0-9]+' | head -1 | awk -F/ '{print $NF}')
	fi

	# 兜底已知稳定版本
	if [[ -z "${new_ver}" ]]; then
		new_ver="v1.25.0"
		echo -e "${Tip} 获取最新版本失败，使用内置版本 [ ${new_ver} ]"
	else
		echo -e "${Info} 检测到 Shadowsocks Rust 最新版本为 [ ${new_ver} ]"
	fi
	return 0
}

check_ver_comparison(){
	now_ver=$(cat "${Now_ver_File}" 2>/dev/null)
	if [[ "${now_ver}" != "${new_ver}" ]]; then
		echo -e "${Info} 发现 Shadowsocks Rust 已有新版本 [ ${new_ver} ]，当前版本 [ ${now_ver} ]"
		read -e -p "是否更新 ？ [Y/n]：" yn
		[[ -z "${yn}" ]] && yn="y"
		if [[ $yn == [Yy] ]]; then
			check_status
			local was_running=0
			[[ "$status" == "running" ]] && was_running=1
			[[ $was_running -eq 1 ]] && service_stop
			\cp "${CONF}" "/tmp/config.json.bak" 2>/dev/null
			Download
			mv -f "/tmp/config.json.bak" "${CONF}" 2>/dev/null
			[[ $was_running -eq 1 ]] && service_start
		fi
	else
		echo -e "${Info} 当前 Shadowsocks Rust 已是最新版本 [ ${new_ver} ] ！" && exit 1
	fi
}

# STREAMING_CHUNK:Downloading binaries from official and backup sources...
stable_Download() {
	echo -e "${Info} 开始下载 Shadowsocks Rust 二进制包 ……"
	local tar_file="" target=""

	# 在 Alpine 或检测到 musl 的系统下，强制优先选择 musl 静态链接版本
	if [[ "${release}" == "alpine" && -n "${arch_musl}" ]]; then
		target="${arch_musl}"
		tar_file="shadowsocks-${new_ver}.${target}.tar.xz"
		echo -e "${Info} 当前为 Alpine 系统，下载 musl 静态构建版 (${target})……"
		wget --no-check-certificate -N "https://github.com/shadowsocks/shadowsocks-rust/releases/download/${new_ver}/${tar_file}"
	elif [[ -n "${arch_musl}" ]]; then
		target="${arch_musl}"
		tar_file="shadowsocks-${new_ver}.${target}.tar.xz"
		echo -e "${Info} 优先下载兼容性更佳的 musl 版本 (${target})……"
		wget --no-check-certificate -N "https://github.com/shadowsocks/shadowsocks-rust/releases/download/${new_ver}/${tar_file}"
		if [[ ! -e "${tar_file}" && -n "${arch_gnu}" ]]; then
			target="${arch_gnu}"
			tar_file="shadowsocks-${new_ver}.${target}.tar.xz"
			echo -e "${Tip} musl 版本下载未成功，尝试下载 gnu 版本 (${target})……"
			wget --no-check-certificate -N "https://github.com/shadowsocks/shadowsocks-rust/releases/download/${new_ver}/${tar_file}"
		fi
	elif [[ -n "${arch_gnu}" ]]; then
		target="${arch_gnu}"
		tar_file="shadowsocks-${new_ver}.${target}.tar.xz"
		echo -e "${Info} 下载 gnu 版本 (${target})……"
		wget --no-check-certificate -N "https://github.com/shadowsocks/shadowsocks-rust/releases/download/${new_ver}/${tar_file}"
	fi

	if [[ -z "${tar_file}" || ! -e "${tar_file}" ]]; then
		echo -e "${Error} Shadowsocks Rust 官方源下载失败！"
		return 1
	fi

	tar -xf "${tar_file}"
	if [[ ! -e "ssserver" ]]; then
		echo -e "${Error} Shadowsocks Rust 解压失败或包内缺少 ssserver！"
		rm -rf "${tar_file}"
		return 1
	fi

	rm -rf "${tar_file}"
	chmod +x ssserver
	mv -f ssserver "${FILE}"
	rm -f sslocal ssmanager ssservice ssurl
	mkdir -p "${FOLDER}"
	echo "${new_ver}" > "${Now_ver_File}"

	echo -e "${Info} Shadowsocks Rust 主程序安装完成！"
	return 0
}

backup_Download() {
	echo -e "${Info} 尝试使用备用源下载 Shadowsocks Rust ……"
	local backup_tar="shadowsocks-v1.25.0.${arch_musl:-${arch_gnu}}.tar.xz"
	wget --no-check-certificate -N "https://github.com/shadowsocks/shadowsocks-rust/releases/download/v1.25.0/${backup_tar}"
	if [[ ! -e "${backup_tar}" ]]; then
		echo -e "${Error} Shadowsocks Rust 备用源下载失败！"
		return 1
	fi
	tar -xf "${backup_tar}"
	if [[ ! -e "ssserver" ]]; then
		echo -e "${Error} Shadowsocks Rust 备用源解压失败 !"
		rm -rf "${backup_tar}"
		return 1
	fi
	rm -rf "${backup_tar}"
	chmod +x ssserver
	mv -f ssserver "${FILE}"
	rm -f sslocal ssmanager ssservice ssurl
	mkdir -p "${FOLDER}"
	echo "v1.25.0" > "${Now_ver_File}"
	echo -e "${Info} Shadowsocks Rust 备用源程序下载安装完毕！"
	return 0
}

Download() {
	mkdir -p "${FOLDER}"
	if ! stable_Download; then
		if ! backup_Download; then
			echo -e "${Error} 所有下载源均失败，请检查网络连接。"
			exit 1
		fi
	fi
}

# STREAMING_CHUNK:Configuring init system services (OpenRC and Systemd)...
Service(){
	if [[ "${init_sys}" == "openrc" ]]; then
		cat > /etc/init.d/ss-rust <<'EOF'
#!/sbin/openrc-run

name="Shadowsocks Rust"
description="Shadowsocks Rust Server Service"
command="/usr/local/bin/ss-rust"
command_args="-c /etc/ss-rust/config.json"
command_background="yes"
pidfile="/run/ss-rust.pid"
output_log="/var/log/ss-rust.log"
error_log="/var/log/ss-rust.log"

depend() {
	need net
	after firewall
}

start_pre() {
	checkpath -f -m 0644 -o root:root /var/log/ss-rust.log
	ulimit -n 51200 2>/dev/null || true
}
EOF
		chmod +x /etc/init.d/ss-rust
		rc-update add ss-rust default 2>/dev/null
	else
		cat > /etc/systemd/system/ss-rust.service <<-EOF
[Unit]
Description=Shadowsocks Rust Service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
LimitNOFILE=51200
Restart=on-failure
RestartSec=5s
ExecStart=/usr/local/bin/ss-rust -c /etc/ss-rust/config.json

[Install]
WantedBy=multi-user.target
EOF
		systemctl daemon-reload
		systemctl enable ss-rust 2>/dev/null
	fi
	echo -e "${Info} Shadowsocks Rust 服务配置完成！"
}

# STREAMING_CHUNK:Installing required packages and toolchains...
Installation_dependency(){
	echo -e "${Info} 正在安装系统基础依赖工具..."
	case "${pkg_mgr}" in
		apk)
			apk update
			apk add --no-cache jq gzip wget curl unzip xz tar ca-certificates openssl tzdata
			;;
		apt-get)
			apt-get update && apt-get install -y jq gzip wget curl unzip xz-utils tar ca-certificates openssl tzdata
			;;
		dnf|yum)
			${pkg_mgr} install -y jq gzip wget curl unzip xz tar ca-certificates openssl tzdata
			;;
		zypper)
			zypper --non-interactive --gpg-auto-import-keys install jq gzip wget curl unzip xz tar ca-certificates timezone
			;;
		pacman)
			pacman -Sy --noconfirm --needed jq gzip wget curl unzip xz tar ca-certificates openssl tzdata
			;;
		*)
			echo -e "${Tip} 未识别的包管理器，请确认系统已安装：jq wget curl tar xz"
			;;
	esac
	[[ -f /usr/share/zoneinfo/Asia/Shanghai ]] && \cp -f /usr/share/zoneinfo/Asia/Shanghai /etc/localtime 2>/dev/null
}

# STREAMING_CHUNK:Managing service life-cycle helper functions...
service_start(){
	if [[ "${init_sys}" == "openrc" ]]; then
		rc-service ss-rust start
	else
		systemctl start ss-rust
	fi
}

service_stop(){
	if [[ "${init_sys}" == "openrc" ]]; then
		rc-service ss-rust stop 2>/dev/null
	else
		systemctl stop ss-rust 2>/dev/null
	fi
}

service_restart(){
	if [[ "${init_sys}" == "openrc" ]]; then
		rc-service ss-rust restart
	else
		systemctl restart ss-rust
	fi
}

# STREAMING_CHUNK:Managing configuration files...
Write_config(){
	mkdir -p "${FOLDER}"
	cat > "${CONF}" <<-EOF
{
    "server": "::",
    "server_port": ${port},
    "password": "${password}",
    "method": "${cipher}",
    "fast_open": ${tfo},
    "mode": "tcp_and_udp",
    "timeout": 300,
    "nameserver": "8.8.8.8"
}
EOF
}

Read_config(){
	[[ ! -e ${CONF} ]] && echo -e "${Error} Shadowsocks Rust 配置文件不存在！" && exit 1
	port=$(jq -r '.server_port // 2525' "${CONF}")
	password=$(jq -r '.password // ""' "${CONF}")
	cipher=$(jq -r '.method // "2022-blake3-chacha20-poly1305"' "${CONF}")
	tfo=$(jq -r '.fast_open // false' "${CONF}")
}

Set_port(){
	while true; do
		echo -e "${Tip} 本步骤不涉及系统防火墙端口操作，请手动放行相应端口！"
		echo -e "请输入 Shadowsocks Rust 端口 [1-65535]"
		read -e -p "(默认：2525)：" port
		[[ -z "${port}" ]] && port="2525"
		if [[ "${port}" =~ ^[0-9]+$ ]] && [ "${port}" -ge 1 ] && [ "${port}" -le 65535 ]; then
			echo && echo "=================================="
			echo -e "端口：${Red_background_prefix} ${port} ${Font_color_suffix}"
			echo "==================================" && echo
			break
		else
			echo -e "${Error} 输入错误, 请输入 1-65535 范围内的端口。"
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
	[[ "${len}" -eq "${need}" ]]
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
			echo -e "${Tip} 当前密码不是 ${keylen} 字节的合法 base64 密钥，已自动纠正重新生成！"
			password=$(Gen_psk "${cipher}")
		fi
	else
		read -e -p "(默认：随机生成)：" password
		[[ -z "${password}" ]] && password=$(Gen_psk "${cipher}")
	fi
	echo && echo "=================================="
	echo -e "密码：${Red_background_prefix} ${password} ${Font_color_suffix}"
	echo "==================================" && echo
}

# STREAMING_CHUNK:Setting cipher algorithms...
Set_cipher(){
	echo -e "请选择 Shadowsocks Rust 加密方式
==================================	
 ${Green_font_prefix} 1.${Font_color_suffix} 2022-blake3-chacha20-poly1305 ${Green_font_prefix}(默认)${Font_color_suffix}
 ${Green_font_prefix} 2.${Font_color_suffix} 2022-blake3-aes-128-gcm ${Green_font_prefix}(推荐)${Font_color_suffix}
 ${Green_font_prefix} 3.${Font_color_suffix} 2022-blake3-aes-256-gcm ${Green_font_prefix}(推荐)${Font_color_suffix}
 ${Green_font_prefix} 4.${Font_color_suffix} aes-128-gcm
 ${Green_font_prefix} 5.${Font_color_suffix} aes-256-gcm
 ${Green_font_prefix} 6.${Font_color_suffix} chacha20-ietf-poly1305
 ${Green_font_prefix} 7.${Font_color_suffix} plain ${Red_font_prefix}(无加密)${Font_color_suffix}
 ${Green_font_prefix} 8.${Font_color_suffix} none  ${Red_font_prefix}(无加密)${Font_color_suffix}
==================================" && echo
	read -e -p "(默认: 1. 2022-blake3-chacha20-poly1305)：" cipher
	[[ -z "${cipher}" ]] && cipher="1"
	case "${cipher}" in
		1) cipher="2022-blake3-chacha20-poly1305" ;;
		2) cipher="2022-blake3-aes-128-gcm" ;;
		3) cipher="2022-blake3-aes-256-gcm" ;;
		4) cipher="aes-128-gcm" ;;
		5) cipher="aes-256-gcm" ;;
		6) cipher="chacha20-ietf-poly1305" ;;
		7) cipher="plain" ;;
		8) cipher="none" ;;
		*) cipher="2022-blake3-chacha20-poly1305" ;;
	esac
	echo && echo "=================================="
	echo -e "加密：${Red_background_prefix} ${cipher} ${Font_color_suffix}"
	echo "==================================" && echo
}

# STREAMING_CHUNK:Configuring settings menu...
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
	Read_config
	if [[ "${modify}" == "1" ]]; then
		Set_port
		Write_config
		Restart
	elif [[ "${modify}" == "2" ]]; then
		Set_password
		Write_config
		Restart
	elif [[ "${modify}" == "3" ]]; then
		Set_cipher
		if [[ "${cipher}" == 2022-blake3-* ]] && ! check_psk "${password}" "${cipher}"; then
			echo -e "${Tip} 原密码不适用于当前 2022 加密，已自动重新生成密钥"
			password=$(Gen_psk "${cipher}")
		fi
		Write_config
		Restart
	elif [[ "${modify}" == "4" ]]; then
		Set_tfo
		Write_config
		Restart
	elif [[ "${modify}" == "5" ]]; then
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

# STREAMING_CHUNK:Installation and service control flows...
Install(){
	[[ -e ${FILE} ]] && echo -e "${Error} 检测到 Shadowsocks Rust 已安装！" && exit 1
	echo -e "${Info} 开始安装/配置 基础依赖..."
	Installation_dependency
	echo -e "${Info} 开始配置 Shadowsocks Rust 参数..."
	Set_port
	Set_cipher
	Set_password
	Set_tfo
	echo -e "${Info} 开始获取程序版本并下载..."
	check_new_ver || exit 1
	Download
	echo -e "${Info} 开始写入 配置文件..."
	Write_config
	echo -e "${Info} 开始安装系统服务脚本..."
	Service
	echo -e "${Info} 所有步骤安装完毕，开始启动..."
	Start
}

Start(){
	check_installed_status
	check_status
	[[ "$status" == "running" ]] && echo -e "${Info} Shadowsocks Rust 已在运行 ！" && sleep 2 && Start_Menu
	service_start
	sleep 1
	check_status
	if [[ "$status" == "running" ]]; then
		echo -e "${Info} Shadowsocks Rust 启动成功 ！"
	else
		echo -e "${Error} Shadowsocks Rust 启动失败，请检查配置或日志！"
		[[ "${init_sys}" == "openrc" && -f /var/log/ss-rust.log ]] && tail -n 10 /var/log/ss-rust.log
	fi
	sleep 2
	Start_Menu
}

Stop(){
	check_installed_status
	check_status
	[[ "$status" != "running" ]] && echo -e "${Error} Shadowsocks Rust 没有运行，无需停止！" && sleep 2 && Start_Menu
	service_stop
	sleep 1
	echo -e "${Info} Shadowsocks Rust 已停止 ！"
	sleep 2
	Start_Menu
}

Restart(){
	check_installed_status
	service_restart
	sleep 1
	echo -e "${Info} Shadowsocks Rust 重启完毕 ！"
	sleep 2
	View
	Start_Menu
}

Update(){
	check_installed_status
	check_new_ver || exit 1
	check_ver_comparison
	echo -e "${Info} Shadowsocks Rust 更新完毕！"
	sleep 2
	Start_Menu
}

# STREAMING_CHUNK:Uninstalling ss-rust and service cleaner...
Uninstall(){
	check_installed_status
	echo "确定要卸载 Shadowsocks Rust ? (y/N)"
	read -e -p "(默认：n)：" unyn
	[[ -z ${unyn} ]] && unyn="n"
	if [[ ${unyn} == [Yy] ]]; then
		check_status
		[[ "$status" == "running" ]] && service_stop
		if [[ "${init_sys}" == "openrc" ]]; then
			rc-update del ss-rust default 2>/dev/null
			rm -f /etc/init.d/ss-rust
		else
			systemctl disable ss-rust 2>/dev/null
			rm -f /etc/systemd/system/ss-rust.service
			systemctl daemon-reload 2>/dev/null
			systemctl reset-failed ss-rust 2>/dev/null
		fi
		rm -rf "${FOLDER}"
		rm -rf "${FILE}"
		echo && echo -e "${Info} Shadowsocks Rust 卸载完成！" && echo
	else
		echo && echo "卸载已取消..." && echo
	fi
	sleep 2
	Start_Menu
}

# STREAMING_CHUNK:Fetching IP addresses and link generation...
getipv4(){
	ipv4=$(wget -qO- -4 -t1 -T2 ipinfo.io/ip 2>/dev/null)
	if [[ -z "${ipv4}" ]]; then
		ipv4=$(wget -qO- -4 -t1 -T2 api.ip.sb/ip 2>/dev/null)
		if [[ -z "${ipv4}" ]]; then
			ipv4=$(wget -qO- -4 -t1 -T2 members.3322.org/dyndns/getip 2>/dev/null)
			[[ -z "${ipv4}" ]] && ipv4="IPv4_Error"
		fi
	fi
}

getipv6(){
	ipv6=$(wget -qO- -6 -t1 -T2 ifconfig.co 2>/dev/null)
	[[ -z "${ipv6}" ]] && ipv6="IPv6_Error"
}

urlsafe_base64(){
	printf "%s" "$1" | base64 | tr -d '\r\n' | tr '+/' '-_' | tr -d '='
}

Gen_QR(){
	if command -v qrencode >/dev/null 2>&1; then
		qrencode -t ANSIUTF8 "$1"
	else
		echo -e " 二维码：未安装 qrencode，无法本地生成二维码图片（可直接使用下方 ss:// 链接）"
	fi
}

Link_QR(){
	link_ipv4=""
	link_ipv6=""
	if [[ "${ipv4}" != "IPv4_Error" && -n "${ipv4}" ]]; then
		SSbase64=$(urlsafe_base64 "${cipher}:${password}@${ipv4}:${port}")
		SSurl="ss://${SSbase64}"
		link_ipv4=" 链接  [IPv4]：${Red_font_prefix}${SSurl}${Font_color_suffix}
$(Gen_QR "${SSurl}")"
	fi
	if [[ "${ipv6}" != "IPv6_Error" && -n "${ipv6}" ]]; then
		SSbase64=$(urlsafe_base64 "${cipher}:${password}@[${ipv6}]:${port}")
		SSurl="ss://${SSbase64}"
		link_ipv6=" 链接  [IPv6]：${Red_font_prefix}${SSurl}${Font_color_suffix}
$(Gen_QR "${SSurl}")"
	fi
}

# STREAMING_CHUNK:Displaying configuration and service status logs...
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
	[[ -n "${link_ipv4}" ]] && echo -e "${link_ipv4}"
	[[ -n "${link_ipv6}" ]] && echo -e "${link_ipv6}"
	echo -e "——————————————————————————————————"
	Before_Start_Menu
}

Status(){
	echo -e "${Info} 获取 Shadowsocks Rust 活动状态/日志 ……"
	if [[ "${init_sys}" == "openrc" ]]; then
		rc-service ss-rust status
		echo -e "\n${Info} 最近 20 行运行日志 (/var/log/ss-rust.log)："
		if [[ -f /var/log/ss-rust.log ]]; then
			tail -n 20 /var/log/ss-rust.log
		else
			echo "暂无日志文件"
		fi
	else
		echo -e "${Tip} 返回请按 q ！"
		systemctl status ss-rust
	fi
	Before_Start_Menu
}

Update_Shell(){
	local sh_url="https://raw.githubusercontent.com/BFDZ/Shadowsocks-Rust/master/ss-rust.sh"
	echo -e "当前脚本版本为 [ ${sh_ver} ]，开始检测最新版本..."
	sh_new_ver=$(wget --no-check-certificate -qO- "${sh_url}" 2>/dev/null | grep 'sh_ver="' | awk -F "=" '{print $NF}' | tr -d '"' | head -1)
	if [[ -z "${sh_new_ver}" ]]; then
		echo -e "${Error} 检测最新版本失败 !"
		sleep 2
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
				sleep 2
				bash "${filepath}/ss-rust.sh"
			else
				echo -e "${Error} 脚本更新失败，请检查网络 !"
				sleep 2
				Start_Menu
			fi
		else
			echo -e "已取消更新..."
			sleep 2
			Start_Menu
		fi
	else
		echo -e "当前已是最新版本[ ${sh_new_ver} ] ！"
		sleep 2
		Start_Menu
	fi
}

Before_Start_Menu() {
    echo && echo -n -e "${Yellow_font_prefix}* 按回车返回主菜单 *${Font_color_suffix}" && read -r temp
    Start_Menu
}

# STREAMING_CHUNK:Rendering main menu...
Start_Menu(){
clear
check_root
check_init
check_sys
sysArch
	echo && echo -e "  
==================================
Shadowsocks Rust 管理脚本 ${Red_font_prefix}[v${sh_ver}]${Font_color_suffix}
系统类型: ${Green_font_prefix}${release}${Font_color_suffix} | 服务管理器: ${Green_font_prefix}${init_sys}${Font_color_suffix}
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
 ${Green_font_prefix} 9.${Font_color_suffix} 查看 运行状态/日志
——————————————————————————————————
 ${Green_font_prefix}10.${Font_color_suffix} 退出脚本
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
		0) Update_Shell ;;
		1) Install ;;
		2) Update ;;
		3) Uninstall ;;
		4) Start ;;
		5) Stop ;;
		6) Restart ;;
		7) Set ;;
		8) View ;;
		9) Status ;;
		10) exit 0 ;;
		*) echo "请输入正确数字 [0-10]" ;;
	esac
}

Start_Menu