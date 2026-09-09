#!/bin/bash
# 一条命令装好：编译 App、装 kagemaku CLI、挂到登录自启
set -e
REPO="$(cd "$(dirname "$0")/.." && pwd)"
CLI="$HOME/.local/bin/kagemaku"

bash "$REPO/scripts/build-app.sh"

mkdir -p "$HOME/.local/bin"
sed "s|__REPO__|$REPO|g" "$REPO/scripts/kagemaku" > "$CLI"
chmod +x "$CLI"

"$CLI" up

echo
echo "CLI 装在 $CLI"
case ":$PATH:" in
    *":$HOME/.local/bin:"*) ;;
    *) echo "提醒：$HOME/.local/bin 不在 PATH 里，加一行到 ~/.zshrc："
       echo '  export PATH="$HOME/.local/bin:$PATH"' ;;
esac
