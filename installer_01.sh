#!/bin/bash

# --- Глобальные переменные ---
ARCH=$(uname -m)
SUDO_PASSWORD=""
INSTALL_LOG="/tmp/setup_log_$(date +%s).txt"
TEMP_FILES=()
BACKTITLE="\Zb\Z2Установка окружения разработчика | $(date +%Y-%m-%d)\Zn"
CONFIG_FILE="setup.conf"
MAX_RETRIES=3
TIMEOUT=300

# --- Модульная структура инструментов ---
declare -A TOOLS=(
    ["PyCharm"]="install_pycharm|IDE для Python"
    ["VSCode"]="install_vscode|Лёгкий редактор кода"
    ["DBeaver"]="install_dbeaver|Клиент для баз данных"
    ["WireGuard"]="install_wireguard|VPN"
    ["kubectl_minikube"]="install_kubectl_minikube|Kubernetes инструменты"
    ["DockerCompose"]="install_docker_compose|Управление контейнерами"
    ["AWSCLI"]="install_awscli|Инструмент для AWS"
    ["Telegram"]="install_telegram|Мессенджер"
    ["Discord"]="install_discord|Чат для команд"
    ["tmux"]="install_tmux|Терминальный мультиплексор"
    ["Postman"]="install_postman|Тестирование API"
    ["zsh"]="install_zsh|Улучшенная оболочка"
    ["httpie"]="install_httpie|Удобный HTTP-клиент"
)

# --- Обработка прерываний ---
trap 'cleanup; exit 1' TERM

# --- Универсальная функция прогресса ---
show_progress() {
    local cmd="$1" title="$2" log_file="/tmp/install_$(date +%s).log"
    TEMP_FILES+=("$log_file")
    (
        echo "0"
        echo "XXX"
        echo "\Zb\Z2$title\Zn"
        echo "XXX"
        local percent=0
        local dots=""
        eval "$cmd" >> "$log_file" 2>&1 &  # Используем eval для корректной обработки сложных команд
        local pid=$!
        while kill -0 $pid 2>/dev/null; do
            percent=$((percent + 2))
            [ $percent -gt 99 ] && percent=99
            dots=$(printf "%.$((percent % 4))s" "....")
            echo "$percent"
            echo "XXX"
            echo "\Zb\Z2$title $dots\Zn"
            echo "XXX"
            sleep 0.5
        done
        wait $pid
        if [ $? -eq 0 ]; then
            echo "100"
            echo "XXX"
            echo "\Zb\Z2$title завершено\Zn"
            echo "XXX"
        else
            echo "0"
            echo "XXX"
            echo "\Zb\Z1Ошибка: $title\Zn"
            echo "XXX"
            check_error "$title (см. $log_file)"
        fi
    ) | dialog --colors --backtitle "$BACKTITLE" --title "$title" --gauge "Пожалуйста, подождите..." 10 70
}

# --- Модульные функции ---
check_error() {
    if [ $? -ne 0 ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Ошибка: $1" >> "$INSTALL_LOG"
        dialog --colors --backtitle "$BACKTITLE" --title "\Zb\Z1Ошибка\Zn" --msgbox "Ошибка: $1\nЛог сохранён в $INSTALL_LOG" 10 50
        exit 1
    fi
}

check_installed() {
    command -v "$1" >/dev/null 2>&1 && return 0 || return 1
}

format_size() {
    local bytes=$1
    if [ "$bytes" -lt 1024 ]; then
        echo "${bytes}B"
    elif [ "$bytes" -lt $((1024 * 1024)) ]; then
        echo "$(echo "scale=2; $bytes / 1024" | bc)KB"
    elif [ "$bytes" -lt $((1024 * 1024 * 1024)) ]; then
        echo "$(echo "scale=2; $bytes / (1024 * 1024)" | bc)MB"
    else
        echo "$(echo "scale=2; $bytes / (1024 * 1024 * 1024)" | bc)GB"
    fi
}

retry_curl() {
    local url=$1 output=$2 attempt=1 size downloaded dots=""
    size=$(curl -sI --connect-timeout 10 "$url" | grep -i Content-Length | awk '{print $2}' | tr -d '\r')
    [ -z "$size" ] && size=0
    while [ $attempt -le $MAX_RETRIES ]; do
        if [ "$size" -gt 0 ]; then
            (
                curl -s --max-time "$TIMEOUT" "$url" -o "$output" 2>>"$INSTALL_LOG" &
                local pid=$!
                local percent=0
                while kill -0 $pid 2>/dev/null; do
                    percent=$((percent + 2))
                    [ $percent -gt 99 ] && percent=99
                    downloaded=$((size * percent / 100))
                    formatted_downloaded=$(format_size "$downloaded")
                    formatted_size=$(format_size "$size")
                    dots=$(printf "%.$((percent % 4))s" "....")
                    echo "$percent"
                    echo "XXX"
                    echo "\Zb\Z2Скачивание: $formatted_downloaded / $formatted_size ($percent%) $dots\Zn"
                    echo "XXX"
                    sleep 0.5
                done
                wait $pid
                [ $? -eq 0 ] && echo "100" || echo "0"
                echo "XXX"
                [ $? -eq 0 ] && echo "\Zb\Z2Скачивание завершено\Zn" || echo "\Zb\Z1Ошибка скачивания\Zn"
                echo "XXX"
            ) | dialog --colors --backtitle "$BACKTITLE" --title "Скачивание $output" --gauge "Пожалуйста, подождите..." 10 70
            [ $? -eq 0 ] && return 0
        else
            show_progress "curl -s --max-time $TIMEOUT $url -o $output" "Скачивание $output"
            [ $? -eq 0 ] && return 0
        fi
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Попытка $attempt из $MAX_RETRIES для $url не удалась" >>"$INSTALL_LOG"
        sleep 2
        attempt=$((attempt + 1))
    done
    check_error "Не удалось скачать $url после $MAX_RETRIES попыток"
}

detect_package_manager() {
    if command -v apt-get >/dev/null 2>&1; then
        PKG_MANAGER="apt-get"
        UPDATE_CMD="apt-get update"
        INSTALL_CMD="apt-get install -y"
        REMOVE_CMD="apt-get remove -y"
    elif command -v yum >/dev/null 2>&1; then
        PKG_MANAGER="yum"
        UPDATE_CMD="yum update -y"
        INSTALL_CMD="yum install -y"
        REMOVE_CMD="yum remove -y"
    elif command -v dnf >/dev/null 2>&1; then
        PKG_MANAGER="dnf"
        UPDATE_CMD="dnf update -y"
        INSTALL_CMD="dnf install -y"
        REMOVE_CMD="dnf remove -y"
    elif command -v pacman >/dev/null 2>&1; then
        PKG_MANAGER="pacman"
        UPDATE_CMD="pacman -Syu --noconfirm"
        INSTALL_CMD="pacman -S --noconfirm"
        REMOVE_CMD="pacman -R --noconfirm"
    elif command -v zypper >/dev/null 2>&1; then
        PKG_MANAGER="zypper"
        UPDATE_CMD="zypper refresh"
        INSTALL_CMD="zypper install -y"
        REMOVE_CMD="zypper remove -y"
    else
        check_error "Не удалось определить пакетный менеджер"
    fi
}

request_sudo_password() {
    SUDO_PASSWORD=$(dialog --colors --backtitle "$BACKTITLE" --insecure --passwordbox "\Zb\Z2Введите пароль для sudo:\Zn" 8 40 3>&1 1>&2 2>&3)
    if [ -z "$SUDO_PASSWORD" ] || ! echo "$SUDO_PASSWORD" | sudo -S -v >/dev/null 2>&1; then
        dialog --colors --backtitle "$BACKTITLE" --title "\Zb\Z1Ошибка\Zn" --msgbox "🚫 Неверный пароль sudo или ввод отменён." 10 50
        exit 1
    fi
}

check_url() {
    show_progress "curl -Is --connect-timeout 10 $1 | head -n 1 | grep -q 200" "Проверка доступности $1"
}

select_version() {
    local tool=$1
    if [ "$tool" = "python" ]; then
        VERSION=$(dialog --colors --backtitle "$BACKTITLE" --menu "\Zb\Z2Выберите версию Python:\Zn" 12 40 5 \
            "3.9" "Python 3.9" \
            "3.10" "Python 3.10" \
            "3.11" "Python 3.11" \
            "3.12" "Python 3.12" \
            "latest" "Последняя стабильная" 2>&1 >/dev/tty)
        check_error "выбор версии Python"
    elif [ "$tool" = "node" ]; then
        VERSION=$(dialog --colors --backtitle "$BACKTITLE" --menu "\Zb\Z2Выберите версию Node.js:\Zn" 12 40 5 \
            "16" "Node.js 16 LTS" \
            "18" "Node.js 18 LTS" \
            "20" "Node.js 20 LTS" \
            "lts" "Последняя LTS" \
            "latest" "Последняя стабильная" 2>&1 >/dev/tty)
        check_error "выбор версии Node.js"
    fi
    echo "$VERSION"
}

backup_file() {
    local file=$1
    [ -f "$file" ] && show_progress "cp $file $file.bak_$(date +%s)" "Создание резервной копии $file"
}

remove_old_version() {
    local pkg=$1 old_ver=$2
    if command -v "$old_ver" >/dev/null 2>&1; then
        dialog --colors --backtitle "$BACKTITLE" --yesno "Обнаружена старая версия $pkg ($old_ver). Удалить?" 8 50
        if [ $? -eq 0 ]; then
            show_progress "echo \"$SUDO_PASSWORD\" | sudo -S $REMOVE_CMD $old_ver" "Удаление старой версии $pkg ($old_ver)"
        fi
    fi
}

install_dialog() {
    if ! check_installed dialog; then
        detect_package_manager
        show_progress "echo \"$SUDO_PASSWORD\" | sudo -S $INSTALL_CMD dialog" "Установка dialog"
    fi
}

install_base_tools() {
    local pkgs=""
    for pkg in pv unzip curl; do
        check_installed "$pkg" || pkgs="$pkgs $pkg"
    done
    if [ -n "$pkgs" ]; then
        show_progress "echo \"$SUDO_PASSWORD\" | sudo -S $INSTALL_CMD $pkgs" "Установка базовых утилит"
    fi
}

install_snap() {
    if ! check_installed snap; then
        if [ "$PKG_MANAGER" = "apt-get" ]; then
            show_progress "echo \"$SUDO_PASSWORD\" | sudo -S $INSTALL_CMD snapd" "Установка snapd"
        elif [ "$PKG_MANAGER" = "yum" ] || [ "$PKG_MANAGER" = "dnf" ]; then
            show_progress "echo \"$SUDO_PASSWORD\" | sudo -S $INSTALL_CMD epel-release snapd" "Установка snapd"
            show_progress "echo \"$SUDO_PASSWORD\" | sudo -S ln -s /var/lib/snapd/snap /snap" "Создание ссылки для snap"
        elif [ "$PKG_MANAGER" = "pacman" ]; then
            show_progress "echo \"$SUDO_PASSWORD\" | sudo -S $INSTALL_CMD snapd" "Установка snapd"
            show_progress "echo \"$SUDO_PASSWORD\" | sudo -S systemctl enable --now snapd.socket" "Активация snapd.socket"
        elif [ "$PKG_MANAGER" = "zypper" ]; then
            show_progress "echo \"$SUDO_PASSWORD\" | sudo -S $INSTALL_CMD snapd" "Установка snapd"
            show_progress "echo \"$SUDO_PASSWORD\" | sudo -S systemctl enable --now snapd" "Активация snapd"
        fi
    fi
}

check_dependencies() {
    show_progress "ping -c 1 1.1.1.1 >/dev/null 2>&1" "Проверка интернета"
    if [ $? -ne 0 ]; then
        check_error "Нет интернета"
    fi
    FREE_SPACE=$(df -h / | awk 'NR==2 {print $4}' | tr -d 'G')
    if [ -z "$FREE_SPACE" ] || [ $(echo "$FREE_SPACE < 5" | bc) -eq 1 ]; then
        check_error "Недостаточно места (требуется 5G)"
    fi
}

update_system() {
    show_progress "echo \"$SUDO_PASSWORD\" | sudo -S $UPDATE_CMD" "Обновление репозиториев"
    if [ $? -ne 0 ]; then
        dialog --colors --backtitle "$BACKTITLE" --title "\Zb\Z3Предупреждение\Zn" --yesno "⚠ Ошибка обновления репозиториев. Продолжить установку?" 10 50
        [ $? -ne 0 ] && check_error "обновление системы"
    fi
}

install_mandatory_components() {
    local pkgs=""
    check_installed curl || pkgs="$pkgs curl"
    check_installed python3 || pkgs="$pkgs python3 python3-pip python3-dev"
    check_installed vim || pkgs="$pkgs vim"
    check_installed git || pkgs="$pkgs git"
    check_installed make || pkgs="$pkgs make"
    [ "$PKG_MANAGER" = "apt-get" ] && check_installed gcc || pkgs="$pkgs build-essential"

    PYTHON_VERSION=$(select_version "python")
    if [ "$PYTHON_VERSION" != "latest" ]; then
        pkgs=$(echo "$pkgs" | sed "s/python3/python3.$PYTHON_VERSION/")
        remove_old_version "Python" "python3.9"
    fi

    if [ -n "$pkgs" ]; then
        show_progress "echo \"$SUDO_PASSWORD\" | sudo -S $INSTALL_CMD $pkgs" "Установка обязательных пакетов"
        show_progress "echo \"$SUDO_PASSWORD\" | sudo -S pip3 install virtualenv pipenv" "Установка virtualenv/pipenv"
    fi
    if ! check_installed docker; then
        show_progress "echo \"$SUDO_PASSWORD\" | sudo -S $INSTALL_CMD docker.io" "Установка Docker"
        show_progress "echo \"$SUDO_PASSWORD\" | sudo -S systemctl enable docker" "Активация Docker"
        show_progress "echo \"$SUDO_PASSWORD\" | sudo -S systemctl start docker" "Запуск Docker"
        show_progress "echo \"$SUDO_PASSWORD\" | sudo -S usermod -aG docker $USER" "Добавление пользователя в группу Docker"
    fi
}

configure_git() {
    GIT_NAME=$(git config --global --get user.name)
    GIT_EMAIL=$(git config --global --get user.email)
    if [ -n "$GIT_NAME" ] && [ -n "$GIT_EMAIL" ]; then
        dialog --colors --backtitle "$BACKTITLE" --yesno "Git уже настроен: $GIT_NAME <$GIT_EMAIL>\nХотите изменить конфигурацию?" 10 50
        if [ $? -eq 0 ]; then
            NEW_GIT_NAME=$(dialog --colors --backtitle "$BACKTITLE" --inputbox "Введите новое имя для Git:" 8 40 "$GIT_NAME" 3>&1 1>&2 2>&3)
            NEW_GIT_EMAIL=$(dialog --colors --backtitle "$BACKTITLE" --inputbox "Введите новый email для Git:" 8 40 "$GIT_EMAIL" 3>&1 1>&2 2>&3)
            if [ -n "$NEW_GIT_NAME" ] && [ -n "$NEW_GIT_EMAIL" ]; then
                show_progress "git config --global user.name \"$NEW_GIT_NAME\"" "Настройка имени Git"
                show_progress "git config --global user.email \"$NEW_GIT_EMAIL\"" "Настройка email Git"
                dialog --colors --backtitle "$BACKTITLE" --msgbox "\Zb\Z2✅ Git обновлён: $NEW_GIT_NAME <$NEW_GIT_EMAIL>\Zn" 10 50
            fi
        fi
    else
        GIT_NAME=$(dialog --colors --backtitle "$BACKTITLE" --inputbox "Введите ваше имя для Git:" 8 40 3>&1 1>&2 2>&3)
        GIT_EMAIL=$(dialog --colors --backtitle "$BACKTITLE" --inputbox "Введите ваш email для Git:" 8 40 3>&1 1>&2 2>&3)
        if [ -n "$GIT_NAME" ] && [ -n "$GIT_EMAIL" ]; then
            show_progress "git config --global user.name \"$GIT_NAME\"" "Настройка имени Git"
            show_progress "git config --global user.email \"$GIT_EMAIL\"" "Настройка email Git"
            dialog --colors --backtitle "$BACKTITLE" --msgbox "\Zb\Z2✅ Git настроен: $GIT_NAME <$GIT_EMAIL>\Zn" 10 50
        fi
    fi
}

install_nvm_node() {
    NODE_VERSION=$(select_version "node")
    local nvm_install_file="/tmp/nvm_install_$(date +%s).sh"
    TEMP_FILES+=("$nvm_install_file")
    if ! check_installed nvm; then
        NVM_URL="https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh"
        check_url "$NVM_URL"
        retry_curl "$NVM_URL" "$nvm_install_file"
        show_progress "chmod +x $nvm_install_file && bash $nvm_install_file" "Установка NVM"
    fi
    mkdir -p "$HOME/.nvm"
    chmod -R u+rwX "$HOME/.nvm"
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    show_progress "nvm install $NODE_VERSION" "Установка Node.js $NODE_VERSION"
}

# --- Функции установки инструментов ---
install_pycharm() {
    if ! check_installed pycharm-community; then
        show_progress "echo \"$SUDO_PASSWORD\" | sudo -S snap install pycharm-community --classic --no-wait" "Установка PyCharm"
    fi
}

install_vscode() {
    if ! check_installed code; then
        show_progress "echo \"$SUDO_PASSWORD\" | sudo -S snap install code --classic --no-wait" "Установка VS Code"
        sleep 2  # Даём время на регистрацию команды в PATH
        if check_installed code; then
            show_progress "code --install-extension ms-python.python" "Установка расширения Python для VS Code"
            show_progress "code --install-extension ms-azuretools.vscode-docker" "Установка расширения Docker для VS Code"
        else
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] Ошибка: VS Code не найден после установки" >> "$INSTALL_LOG"
        fi
    fi
}

install_dbeaver() {
    if ! check_installed dbeaver-ce; then
        show_progress "echo \"$SUDO_PASSWORD\" | sudo -S snap install dbeaver-ce --no-wait" "Установка DBeaver"
    fi
}

install_wireguard() {
    if ! check_installed wg; then
        show_progress "echo \"$SUDO_PASSWORD\" | sudo -S $INSTALL_CMD wireguard" "Установка WireGuard"
    fi
}

install_kubectl_minikube() {
    if ! check_installed kubectl; then
        KUBECTL_URL="https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/$([ "$ARCH" = "aarch64" ] && echo "arm64" || echo "amd64")/kubectl"
        check_url "$KUBECTL_URL"
        retry_curl "$KUBECTL_URL" "kubectl"
        show_progress "chmod +x kubectl && echo \"$SUDO_PASSWORD\" | sudo -S mv kubectl /usr/local/bin/" "Установка kubectl"
    fi
    if ! check_installed minikube; then
        MINIKUBE_URL="https://storage.googleapis.com/minikube/releases/latest/minikube-linux-$([ "$ARCH" = "aarch64" ] && echo "arm64" || echo "amd64")"
        check_url "$MINIKUBE_URL"
        retry_curl "$MINIKUBE_URL" "minikube-linux-$([ "$ARCH" = "aarch64" ] && echo "arm64" || echo "amd64")"
        show_progress "echo \"$SUDO_PASSWORD\" | sudo -S install minikube-linux-$([ "$ARCH" = "aarch64" ] && echo "arm64" || echo "amd64") /usr/local/bin/minikube" "Установка minikube"
        TEMP_FILES+=("minikube-linux-$([ "$ARCH" = "aarch64" ] && echo "arm64" || echo "amd64")")
    fi
}

install_docker_compose() {
    if ! check_installed docker-compose; then
        DOCKER_COMPOSE_URL="https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$([ "$ARCH" = "aarch64" ] && echo "aarch64" || echo "x86_64")"
        check_url "$DOCKER_COMPOSE_URL"
        retry_curl "$DOCKER_COMPOSE_URL" "/usr/local/bin/docker-compose"
        show_progress "echo \"$SUDO_PASSWORD\" | sudo -S chmod +x /usr/local/bin/docker-compose" "Установка Docker Compose"
    fi
}

install_awscli() {
    if ! check_installed aws; then
        show_progress "echo \"$SUDO_PASSWORD\" | sudo -S pip3 install awscli" "Установка AWS CLI"
    fi
}

install_telegram() {
    if ! check_installed telegram-desktop; then
        show_progress "echo \"$SUDO_PASSWORD\" | sudo -S snap install telegram-desktop --no-wait" "Установка Telegram"
    fi
}

install_discord() {
    if ! check_installed discord; then
        show_progress "echo \"$SUDO_PASSWORD\" | sudo -S snap install discord --no-wait" "Установка Discord"
    fi
}

install_tmux() {
    if ! check_installed tmux; then
        show_progress "echo \"$SUDO_PASSWORD\" | sudo -S $INSTALL_CMD tmux" "Установка tmux"
    fi
}

install_postman() {
    if ! check_installed postman; then
        show_progress "echo \"$SUDO_PASSWORD\" | sudo -S snap install postman --no-wait" "Установка Postman"
    fi
}

install_zsh() {
    if ! check_installed zsh; then
        show_progress "echo \"$SUDO_PASSWORD\" | sudo -S $INSTALL_CMD zsh" "Установка zsh"
        show_progress "sh -c \"\$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)\" --unattended" "Установка Oh My Zsh"
        backup_file "$HOME/.zshrc"
        show_progress "sed -i 's/ZSH_THEME=\"robbyrussell\"/ZSH_THEME=\"agnoster\"/' \"$HOME/.zshrc\"" "Настройка темы zsh"
        echo "plugins=(git docker kubectl python)" >> "$HOME/.zshrc"
        if [ ! -d "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-autosuggestions" ]; then
            show_progress "git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-autosuggestions" "Установка плагина zsh-autosuggestions"
        fi
        if [ ! -d "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting" ]; then
            show_progress "git clone https://github.com/zsh-users/zsh-syntax-highlighting ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting" "Установка плагина zsh-syntax-highlighting"
        fi
        echo "source ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh" >> "$HOME/.zshrc"
        echo "source ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" >> "$HOME/.zshrc"
    fi
}

install_httpie() {
    if ! check_installed http; then
        show_progress "echo \"$SUDO_PASSWORD\" | sudo -S pip3 install httpie" "Установка httpie"
    fi
}

select_optional_components() {
    if [ -f "$CONFIG_FILE" ]; then
        dialog --colors --backtitle "$BACKTITLE" --yesno "Найден файл конфигурации $CONFIG_FILE. Использовать его?" 8 50
        if [ $? -eq 0 ]; then
            CHOICES=$(cat "$CONFIG_FILE")
            return
        fi
    fi
    local checklist=()
    for tool in "${!TOOLS[@]}"; do
        IFS='|' read -r func desc <<< "${TOOLS[$tool]}"
        checklist+=("$tool" "$desc" "off")
    done
    dialog --colors --backtitle "$BACKTITLE" --checklist "\Zb\Z2Выберите компоненты для установки:\Zn" 25 70 17 "${checklist[@]}" 2>/tmp/choices.txt
    TEMP_FILES+=("/tmp/choices.txt")
    CHOICES=$(cat /tmp/choices.txt)
    if [ -n "$CHOICES" ]; then
        dialog --colors --backtitle "$BACKTITLE" --yesno "Сохранить выбор в $CONFIG_FILE?" 8 50
        [ $? -eq 0 ] && echo "$CHOICES" > "$CONFIG_FILE"
    fi
}

install_optional_components() {
    if [ -n "$CHOICES" ]; then
        TOTAL_STEPS=$(echo "$CHOICES" | wc -w)
        STEP=0
        (
            echo "0"
            echo "XXX"
            echo "\Zb\Z2Начало установки опциональных компонентов\Zn"
            echo "XXX"
            sleep 1
            for tool in $CHOICES; do
                tool=$(echo "$tool" | tr -d '"')
                if [[ -n "${TOOLS[$tool]}" ]]; then
                    STEP=$((STEP + 1))
                    percent=$((STEP * 100 / TOTAL_STEPS))
                    echo "$percent"
                    echo "XXX"
                    echo "\Zb\Z2Установка $tool ($STEP/$TOTAL_STEPS)\Zn"
                    echo "XXX"
                    IFS='|' read -r install_func desc <<< "${TOOLS[$tool]}"
                    "$install_func"
                fi
            done
            echo "100"
            echo "XXX"
            echo "\Zb\Z2Установка опциональных компонентов завершена\Zn"
            echo "XXX"
        ) | dialog --colors --backtitle "$BACKTITLE" --title "Установка опциональных компонентов" --gauge "Пожалуйста, подождите..." 10 70
    fi
}

check_versions() {
    VERSIONS="🔍 Установленные версии:\n\n"
    VERSIONS="$VERSIONS$(python3 --version 2>/dev/null || echo "Python не установлен")\n"
    VERSIONS="$VERSIONS$(check_installed virtualenv && virtualenv --version || echo "virtualenv не установлен")\n"
    VERSIONS="$VERSIONS$(check_installed pipenv && pipenv --version || echo "pipenv не установлен")\n"
    VERSIONS="$VERSIONS$(docker --version 2>/dev/null || echo "Docker не установлен")\n"
    VERSIONS="$VERSIONS$(check_installed pycharm-community && pycharm-community --version 2>/dev/null || echo "PyCharm не установлен")\n"
    VERSIONS="$VERSIONS$(check_installed code && code --version 2>/dev/null || echo "VS Code не установлен")\n"
    VERSIONS="$VERSIONS$(check_installed dbeaver-ce && dbeaver-ce --version 2>/dev/null || echo "DBeaver не установлен")\n"
    VERSIONS="$VERSIONS$(vim --version | head -n 1 2>/dev/null || echo "Vim не установлен")\n"
    VERSIONS="$VERSIONS$(node --version 2>/dev/null || echo "Node.js не установлен (перезапустите терминал)")\n"
    VERSIONS="$VERSIONS$(git --version 2>/dev/null || echo "Git не установлен")\n"
    VERSIONS="$VERSIONS$(check_installed wg && wg --version 2>/dev/null || echo "WireGuard не установлен")\n"
    VERSIONS="$VERSIONS$(check_installed telegram-desktop && telegram-desktop --version 2>/dev/null || echo "Telegram не установлен")\n"
    VERSIONS="$VERSIONS$(check_installed discord && discord --version 2>/dev/null || echo "Discord не установлен")\n"
    VERSIONS="$VERSIONS$(check_installed tmux && tmux -V || echo "tmux не установлен")\n"
    VERSIONS="$VERSIONS$(check_installed postman && postman --version 2>/dev/null || echo "Postman не установлен")\n"
    VERSIONS="$VERSIONS$(check_installed kubectl && kubectl version --client || echo "kubectl не установлен")\n"
    VERSIONS="$VERSIONS$(check_installed minikube && minikube version || echo "minikube не установлен")\n"
    VERSIONS="$VERSIONS$(check_installed docker-compose && docker-compose --version || echo "Docker Compose не установлен")\n"
    VERSIONS="$VERSIONS$(check_installed zsh && zsh --version || echo "zsh не установлен")\n"
    VERSIONS="$VERSIONS$(check_installed aws && aws --version || echo "AWS CLI не установлен")\n"
    VERSIONS="$VERSIONS$(check_installed http && http --version || echo "httpie не установлен")\n"
    dialog --colors --backtitle "$BACKTITLE" --title "\Zb\Z2Проверка версий\Zn" --msgbox "$VERSIONS" 25 70
}

test_installation() {
    TEST_RESULTS="🛠 Тестирование установки:\n\n"
    TEST_RESULTS="$TEST_RESULTS$(check_installed python3 && echo "✅ Python работает" || echo "❌ Python не работает")\n"
    TEST_RESULTS="$TEST_RESULTS$(check_installed docker && docker run --rm hello-world >/dev/null 2>&1 && echo "✅ Docker работает" || echo "❌ Docker не работает")\n"
    TEST_RESULTS="$TEST_RESULTS$(check_installed git && git --version >/dev/null 2>&1 && echo "✅ Git работает" || echo "❌ Git не работает")\n"
    TEST_RESULTS="$TEST_RESULTS$(check_installed zsh && zsh -c "exit" >/dev/null 2>&1 && echo "✅ zsh работает" || echo "❌ zsh не работает")\n"
    TEST_RESULTS="$TEST_RESULTS$(check_installed code && code --list-extensions | grep -q ms-python.python && echo "✅ VS Code и расширения работают" || echo "❌ VS Code или расширения не работают")\n"
    TEST_RESULTS="$TEST_RESULTS$(check_installed node && node -e "console.log('Node.js OK')" >/dev/null 2>&1 && echo "✅ Node.js работает" || echo "❌ Node.js не работает")\n"
    TEST_RESULTS="$TEST_RESULTS$(check_installed aws && aws --version >/dev/null 2>&1 && echo "✅ AWS CLI работает" || echo "❌ AWS CLI не работает")\n"
    TEST_RESULTS="$TEST_RESULTS$(check_installed kubectl && kubectl version --client >/dev/null 2>&1 && echo "✅ kubectl работает" || echo "❌ kubectl не работает")\n"
    dialog --colors --backtitle "$BACKTITLE" --title "\Zb\Z2Тестирование установки\Zn" --msgbox "$TEST_RESULTS" 15 60
}

cleanup() {
    for file in "${TEMP_FILES[@]}"; do
        [ -f "$file" ] && rm -f "$file" && echo "Удалён $file" >>"$INSTALL_LOG"
    done
    dialog --colors --backtitle "$BACKTITLE" --msgbox "\Zb\Z2🎉 Установка завершена!\Zn\nЛог сохранён в $INSTALL_LOG\nДля применения изменений выполните 'zsh' или перезапустите терминал.\nПолезные команды:\n- nvm use $NODE_VERSION\n- aws configure" 12 60
    if check_installed zsh; then
        dialog --colors --backtitle "$BACKTITLE" --yesno "Хотите сделать zsh оболочкой по умолчанию?" 8 50
        if [ $? -eq 0 ]; then
            show_progress "echo \"$SUDO_PASSWORD\" | sudo -S chsh -s $(which zsh) $USER" "Установка zsh как оболочки по умолчанию"
            dialog --colors --backtitle "$BACKTITLE" --msgbox "\Zb\Z2✅ zsh установлен как оболочка по умолчанию.\Zn\nПерезапустите терминал для применения." 10 50
        fi
    fi
}

# --- Основной процесс ---
if [ "$ARCH" != "x86_64" ] && [ "$ARCH" != "aarch64" ]; then
    echo "Предупреждение: скрипт оптимизирован для x86_64 и aarch64. Некоторые компоненты могут не работать на $ARCH" >>"$INSTALL_LOG"
fi

detect_package_manager
request_sudo_password
install_dialog
install_base_tools
install_snap
check_dependencies
update_system
install_mandatory_components
configure_git
install_nvm_node
select_optional_components
install_optional_components
check_versions
test_installation
cleanup