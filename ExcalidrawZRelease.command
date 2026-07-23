#!/bin/zsh

set -u

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT_DIR" || exit 1

if [[ ! -t 0 ]]; then
  echo "ExcalidrawZ Release Console 需要在交互式终端中运行。"
  exit 1
fi

PBX_PATH="ExcalidrawZ.xcodeproj/project.pbxproj"
RELEASE_VERSION=""
PREVIEW_DEVICE=""
PREVIEW_LOCALES=""

current_version() {
  awk '
    /MARKETING_VERSION =/ {
      value = $3
      gsub(/;/, "", value)
      print value
      exit
    }
  ' "$PBX_PATH"
}

current_build() {
  awk '
    /CURRENT_PROJECT_VERSION =/ {
      value = $3
      gsub(/;/, "", value)
      print value
      exit
    }
  ' "$PBX_PATH"
}

pause() {
  echo
  read "?按回车返回菜单..."
}

select_option() {
  local title="$1"
  shift

  local -a option_keys
  local -a option_labels
  local -a option_descriptions
  local option rest
  local option_count=0

  for option in "$@"; do
    (( option_count += 1 ))
    option_keys[$option_count]="${option%%|*}"
    rest="${option#*|}"
    option_labels[$option_count]="${rest%%|*}"
    if [[ "$rest" == "${option_labels[$option_count]}" ]]; then
      option_descriptions[$option_count]=""
    else
      option_descriptions[$option_count]="${rest#*|}"
    fi
  done

  local selected=1
  local key rest_key i marker

  while true; do
    printf "\033[2J\033[H" >&2
    print -u2 -- "$title"
    print -u2 -- ""

    for (( i = 1; i <= option_count; i++ )); do
      if [[ $i -eq $selected ]]; then
        marker=">"
        printf "\033[7m  %s %s\033[0m\n" "$marker" "${option_labels[$i]}" >&2
      else
        marker=" "
        printf "  %s %s\n" "$marker" "${option_labels[$i]}" >&2
      fi

    done

    print -u2 -- ""
    printf "  %-72s\n" "${option_descriptions[$selected]}" >&2
    print -u2 -- ""
    print -u2 -- "Up/Down 或 j/k 移动，Enter 选择。"

    if ! IFS= read -rs -k 1 key; then
      echo "${option_keys[$selected]}"
      return 0
    fi

    case "$key" in
      $'\x1b')
        IFS= read -rs -k 2 rest_key
        case "$rest_key" in
          "[A"|"OA") (( selected -= 1 )) ;;
          "[B"|"OB") (( selected += 1 )) ;;
        esac
        ;;
      ""|$'\n'|$'\r')
        echo "${option_keys[$selected]}"
        return 0
        ;;
      j|J)
        (( selected += 1 ))
        ;;
      k|K)
        (( selected -= 1 ))
        ;;
      b|B)
        for (( i = 1; i <= option_count; i++ )); do
          if [[ "${option_keys[$i]}" == "back" ]]; then
            echo "back"
            return 0
          fi
        done
        ;;
      q|Q)
        for (( i = 1; i <= option_count; i++ )); do
          if [[ "${option_keys[$i]}" == "quit" ]]; then
            echo "quit"
            return 0
          fi
        done
        for (( i = 1; i <= option_count; i++ )); do
          if [[ "${option_keys[$i]}" == "back" ]]; then
            echo "back"
            return 0
          fi
        done
        ;;
    esac

    if [[ $selected -lt 1 ]]; then
      selected=$option_count
    elif [[ $selected -gt $option_count ]]; then
      selected=1
    fi
  done
}

require_fastlane() {
  if command -v fastlane >/dev/null 2>&1; then
    return 0
  fi

  echo "找不到 fastlane。请先运行: brew install fastlane"
  return 1
}

run_cmd() {
  local title="$1"
  shift

  echo
  echo "== $title =="
  printf "命令:"
  printf " %q" "$@"
  echo
  echo

  "$@"
  local exit_code=$?

  echo
  if [[ $exit_code -eq 0 ]]; then
    echo "完成: $title"
  else
    echo "失败: $title (exit $exit_code)"
  fi
  return $exit_code
}

run_fastlane() {
  local title="$1"
  shift
  require_fastlane || return 1
  run_cmd "$title" fastlane "$@"
}

read_release_version() {
  local default_version
  local version

  default_version="$(current_version)"
  read "?版本号 [$default_version]: " version
  if [[ -z "$version" ]]; then
    version="$default_version"
  fi

  if [[ ! "$version" =~ '^[0-9]+[.][0-9]+[.][0-9]+$' ]]; then
    echo "版本号格式不正确，需要类似 2.2.8"
    return 1
  fi

  RELEASE_VERSION="$version"
}

run_metadata() {
  local platform="$1"
  local dry_run="$2"
  local title_suffix=""
  local -a args

  read_release_version || return 1
  args=(upload_metadata "platform:$platform" "version:$RELEASE_VERSION")
  if [[ "$dry_run" == "true" ]]; then
    args+=("dry_run:true")
    title_suffix=" dry run"
  fi

  run_fastlane "${platform:u} metadata$title_suffix" "${args[@]}"
}

run_ios_release_assets() {
  local dry_run="$1"
  local title_suffix=""
  local -a args

  read_release_version || return 1
  args=(upload_ios_release_assets "version:$RELEASE_VERSION")
  if [[ "$dry_run" == "true" ]]; then
    args+=("dry_run:true")
    title_suffix=" dry run"
  fi

  run_fastlane "iOS metadata + screenshots$title_suffix" "${args[@]}"
}

metadata_menu() {
  local choice

  choice="$(select_option "App Store Connect\n版本默认读取 Xcode MARKETING_VERSION。上传 build 仍由 Xcode Organizer 完成。" \
    "mac_dry|macOS metadata dry run|校验并生成 staged metadata，不上传。" \
    "mac_upload|Upload macOS metadata|上传 macOS metadata 和 release notes。" \
    "ios_dry|iOS metadata dry run|校验并生成 staged metadata，不上传。" \
    "ios_upload|Upload iOS metadata|上传 iOS/iPadOS metadata 和 release notes。" \
    "ios_assets_dry|iOS release assets dry run|校验 iOS metadata 和 screenshots，不上传。" \
    "ios_assets_upload|Upload iOS release assets|上传 iOS metadata 及 iPhone/iPad screenshots。" \
    "back|Back")"

  case "$choice" in
    mac_dry) run_metadata mac true ;;
    mac_upload) run_metadata mac false ;;
    ios_dry) run_metadata ios true ;;
    ios_upload) run_metadata ios false ;;
    ios_assets_dry) run_ios_release_assets true ;;
    ios_assets_upload) run_ios_release_assets false ;;
    back) return 0 ;;
    *) echo "无效选择"; return 1 ;;
  esac
}

choose_preview_device() {
  local choice
  choice="$(select_option "选择截图设备" \
    "iphone|iPhone" \
    "ipad|iPad" \
    "back|Back")"

  case "$choice" in
    iphone|ipad)
      PREVIEW_DEVICE="$choice"
      return 0
      ;;
    back)
      return 1
      ;;
    *)
      echo "无效选择"
      return 1
      ;;
  esac
}

read_preview_locales() {
  local locales
  read "?Locales，逗号分隔；留空生成全部: " locales
  PREVIEW_LOCALES="$locales"
}

run_preview_lane() {
  local lane="$1"
  local title="$2"
  local asks_locales="$3"
  local dry_run="$4"
  local -a args

  choose_preview_device || return 0
  PREVIEW_LOCALES=""
  if [[ "$asks_locales" == "true" ]]; then
    read_preview_locales
  fi

  args=("$lane" "device:$PREVIEW_DEVICE")
  if [[ -n "$PREVIEW_LOCALES" ]]; then
    args+=("locales:$PREVIEW_LOCALES")
  fi
  if [[ "$dry_run" == "true" ]]; then
    args+=("dry_run:true")
  fi

  run_fastlane "$title ($PREVIEW_DEVICE)" "${args[@]}"
}

screenshots_menu() {
  local choice

  choice="$(select_option "App Store Screenshots" \
    "samples|Generate en-US + zh-Hans samples|渲染并分割两个语言，用于快速检查。" \
    "generate|Generate localized screenshots|渲染 localized strips 并分割最终截图。" \
    "generate_dry|Generate screenshots dry run|检查参数和文件路径，不写输出。" \
    "render|Render preview strips only|只生成带文字的完整长图。" \
    "split|Split preview strips only|只把已有长图分割到 screenshots。" \
    "split_dry|Split screenshots dry run|检查分割参数，不写输出。" \
    "back|Back")"

  case "$choice" in
    samples) run_preview_lane generate_preview_samples "Generate preview samples" false false ;;
    generate) run_preview_lane generate_previews "Generate previews" true false ;;
    generate_dry) run_preview_lane generate_previews "Generate previews dry run" true true ;;
    render) run_preview_lane render_preview_strips "Render preview strips" true false ;;
    split) run_preview_lane split_screenshots "Split screenshots" true false ;;
    split_dry) run_preview_lane split_screenshots "Split screenshots dry run" true true ;;
    back) return 0 ;;
    *) echo "无效选择"; return 1 ;;
  esac
}

generate_sparkle_release_notes() {
  read_release_version || return 1
  run_fastlane \
    "Generate Sparkle release notes" \
    mac generate_sparkle_release_notes "version:$RELEASE_VERSION"
}

sparkle_menu() {
  local choice

  choice="$(select_option "Sparkle" \
    "generate|Generate localized release notes|从 macOS metadata 生成 HTML，并更新已有 appcast item。" \
    "back|Back")"

  case "$choice" in
    generate) generate_sparkle_release_notes ;;
    back) return 0 ;;
    *) echo "无效选择"; return 1 ;;
  esac
}

env_is_configured() {
  local env_path="fastlane/.env.local"
  [[ -f "$env_path" ]] || return 1
  grep -q '^APP_STORE_CONNECT_API_KEY_ID=' "$env_path" &&
    grep -q '^APP_STORE_CONNECT_API_ISSUER_ID=' "$env_path" &&
    grep -q '^APP_STORE_CONNECT_API_KEY_PATH=' "$env_path"
}

show_status() {
  echo
  echo "项目目录: $ROOT_DIR"
  echo "版本: $(current_version) ($(current_build))"
  if command -v fastlane >/dev/null 2>&1; then
    echo "fastlane: $(command -v fastlane)"
  else
    echo "fastlane: 未安装"
  fi
  if env_is_configured; then
    echo "App Store Connect API: 已配置 fastlane/.env.local"
  else
    echo "App Store Connect API: 配置不完整"
  fi
  echo
  echo "Preview assets:"
  [[ -f fastlane/previews/assets/iphone/AppStore_iPhone_Previews.png ]] && echo "  iPhone: 已准备" || echo "  iPhone: 缺少底图"
  [[ -f fastlane/previews/assets/ipad/AppStore_iPad_Previews.png ]] && echo "  iPad: 已准备" || echo "  iPad: 缺少底图"
}

tools_menu() {
  local choice

  choice="$(select_option "Tools" \
    "status|Show status|检查版本、fastlane、API 凭证和 preview assets。" \
    "lanes|List fastlane lanes|列出当前 Fastfile 提供的 lanes。" \
    "open_fastlane|Open fastlane folder|在 Finder 中打开 fastlane 目录。" \
    "open_metadata|Open metadata folders|打开 shared、iOS 和 macOS metadata 目录。" \
    "open_previews|Open preview assets|打开 App Store preview 底图目录。" \
    "open_screenshots|Open generated screenshots|打开生成的 localized screenshots 目录。" \
    "back|Back")"

  case "$choice" in
    status) show_status ;;
    lanes) run_fastlane "List fastlane lanes" lanes ;;
    open_fastlane) run_cmd "Open fastlane folder" open "$ROOT_DIR/fastlane" ;;
    open_metadata) run_cmd "Open metadata folders" open "$ROOT_DIR/fastlane/metadata" "$ROOT_DIR/fastlane/metadata-ios" "$ROOT_DIR/fastlane/metadata-mac" ;;
    open_previews) run_cmd "Open preview assets" open "$ROOT_DIR/fastlane/previews/assets" ;;
    open_screenshots) run_cmd "Open screenshots" open "$ROOT_DIR/fastlane/screenshots" ;;
    back) return 0 ;;
    *) echo "无效选择"; return 1 ;;
  esac
}

print_menu() {
  select_option "ExcalidrawZ Release Console\n目录: $ROOT_DIR\n版本: $(current_version) ($(current_build))" \
    "metadata|App Store Connect|上传 macOS/iOS metadata 和 iOS release assets。" \
    "screenshots|Screenshots|渲染并分割 iPhone/iPad 多语言 App Store 截图。" \
    "sparkle|Sparkle|生成多语言 Sparkle release notes 并更新 appcast。" \
    "tools|Tools|检查配置、列出 lanes 或打开相关目录。" \
    "quit|Quit|退出 Release Console。"
}

while true; do
  choice="$(print_menu)"
  case "$choice" in
    metadata) metadata_menu; pause ;;
    screenshots) screenshots_menu; pause ;;
    sparkle) sparkle_menu; pause ;;
    tools) tools_menu; pause ;;
    quit) exit 0 ;;
    *) echo "无效选择"; pause ;;
  esac
done
