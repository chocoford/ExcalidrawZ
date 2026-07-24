#!/bin/bash

set -euo pipefail

log() {
  printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*"
}

section() {
  printf '\n'
  log "== $* =="
}

kv() {
  printf '[%s]    %-18s %s\n' "$(date '+%H:%M:%S')" "$1" "$2"
}

usage() {
  cat <<'EOF'
Usage:
  fastlane/scripts/generate_github_appcast.command [options]

Options:
  --version VERSION              Require the generated appcast to match VERSION.
  --skip-github-asset-check      Prepare publishable files before the GitHub
                                 release asset is reachable.
  --metadata-dir PATH            Release notes directory. Defaults to
                                 ./fastlane/metadata-mac.
  -h, --help                     Show this help.

Fixed paths:
  archive dir            ./archives-new
  public downloads dir   ./WebPage/public/downloads
  output appcast         ./WebPage/public/downloads/appcast.xml
  feed base URL          https://excalidrawz.chocoford.com/downloads/
  GitHub repo            chocoford/ExcalidrawZ

This script asks Sparkle to generate a fresh full-only candidate appcast from
./archives-new, writes localized release notes and the website appcast, and
optionally checks that the matching GitHub release asset is already reachable.
It does not create or upload GitHub releases.
EOF
}

on_error() {
  local status=$?
  log "ERROR Failed at line ${BASH_LINENO[0]} with exit code ${status}"
  exit "$status"
}

require_file() {
  local path="$1"
  local label="$2"

  if [ ! -f "$path" ]; then
    log "ERROR $label does not exist: $path"
    exit 1
  fi
}

url_encode_filename() {
  /usr/bin/ruby -rcgi -e 'print CGI.escape(ARGV.fetch(0)).gsub("+", "%20")' "$1"
}

github_release_asset_name() {
  /usr/bin/ruby -e '
name = ARGV.fetch(0)
ext = File.extname(name)
base = File.basename(name, ext)
base = base.gsub(/[^\p{Alnum}._-]+/, ".")
base = base.gsub(/\.+/, ".").sub(/\A\./, "").sub(/\.\z/, "")
print "#{base}#{ext}"
' "$1"
}

verify_github_asset_uploaded() {
  local url="$1"
  local tag="$2"
  local asset_name="$3"

  if ! command -v curl >/dev/null 2>&1; then
    log "ERROR curl is required to verify GitHub release assets"
    exit 1
  fi

  if ! curl --fail --location --head --silent --show-error --output /dev/null "$url"; then
    log "ERROR GitHub release asset is not reachable: $url"
    log "ERROR Create release $tag and upload asset: $asset_name"
    exit 1
  fi
}

read_candidate_appcast_metadata() {
  /usr/bin/ruby - "$1" <<'RUBY'
require "rexml/document"
require "uri"

path = ARGV.fetch(0)
doc = REXML::Document.new(File.read(path))

def child_text(element, suffix)
  element.elements.each do |child|
    return child.text.to_s.strip if child.name == suffix || child.expanded_name.end_with?(":#{suffix}")
  end
  ""
end

def delta_enclosure?(enclosure)
  enclosure.attributes.each_attribute do |attribute|
    name = attribute.name.to_s
    expanded_name = attribute.expanded_name.to_s
    return true if name == "deltaFrom" || name == "sparkle:deltaFrom" || expanded_name.end_with?(":deltaFrom")
  end
  false
end

REXML::XPath.each(doc, "//item") do |item|
  build = child_text(item, "version").to_i
  short_version = child_text(item, "shortVersionString")
  enclosure_url = nil

  item.elements.each("enclosure") do |enclosure|
    next if delta_enclosure?(enclosure)

    enclosure_url = enclosure.attributes["url"].to_s
    break
  end

  next if build <= 0 || short_version.empty? || enclosure_url.empty?
  asset_name = URI.decode_www_form_component(File.basename(URI.parse(enclosure_url).path))
  puts [build, short_version, asset_name].join("\t")
end
RUBY
}

link_archive_files_to_work_dir() {
  local linked=0

  if [ -n "$EXPECTED_ARCHIVE_PATH" ]; then
    ln -s "$EXPECTED_ARCHIVE_PATH" "$SOURCE_WORK_DIR/$(basename "$EXPECTED_ARCHIVE_PATH")"
    linked=1

    local legacy_release_notes="${EXPECTED_ARCHIVE_PATH%.*}.html"
    if [ -f "$legacy_release_notes" ]; then
      ln -s "$legacy_release_notes" "$SOURCE_WORK_DIR/$(basename "$legacy_release_notes")"
      linked=$((linked + 1))
    fi

    kv "linked archive files" "$linked"
    return
  fi

  while IFS= read -r -d '' file; do
    ln -s "$file" "$SOURCE_WORK_DIR/$(basename "$file")"
    linked=$((linked + 1))
  done < <(find "$ARCHIVES_DIR" -maxdepth 1 -type f -print0)

  kv "linked archive files" "$linked"
}

clean_public_downloads() {
  local expected_dir="$ROOT_DIR/WebPage/public/downloads"

  if [ "$PUBLIC_DIR" != "$expected_dir" ]; then
    log "ERROR Refusing to clean unexpected public downloads dir: $PUBLIC_DIR"
    exit 1
  fi

  mkdir -p "$PUBLIC_DIR"

  local removed
  removed=$(find "$PUBLIC_DIR" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')
  find "$PUBLIC_DIR" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
  kv "removed files" "$removed"
}

write_localized_release_notes() {
  local version="$1"
  local output_base_name="$2"

  /usr/bin/ruby - "$version" "$output_base_name" "$PUBLIC_DIR" "$FASTLANE_METADATA_DIR" <<'RUBY'
require "cgi"
require "fileutils"

version, output_base_name, public_dir, metadata_dir = ARGV
note_paths = Dir.glob(File.join(metadata_dir, "*", "release_notes.txt")).sort
exit 0 if note_paths.empty?

def html_for_release_notes(version, locale, text)
  lines = text.lines.map(&:chomp)
  body = []
  in_list = false

  lines.each do |line|
    stripped = line.strip
    if stripped.empty?
      next
    elsif stripped.start_with?("- ")
      unless in_list
        body << "<ul>"
        in_list = true
      end
      body << "  <li>#{CGI.escapeHTML(stripped.delete_prefix("- ").strip)}</li>"
    else
      if in_list
        body << "</ul>"
        in_list = false
      end
      body << "<p>#{CGI.escapeHTML(stripped)}</p>"
    end
  end

  body << "</ul>" if in_list
  direction = locale.start_with?("ar") ? "rtl" : "ltr"

  <<~HTML
  <!doctype html>
  <html lang="#{CGI.escapeHTML(locale)}" dir="#{direction}">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>ExcalidrawZ #{CGI.escapeHTML(version)}</title>
    <style>
      :root { color-scheme: light dark; }
      body {
        margin: 0;
        padding: 24px;
        font: -apple-system-body;
        line-height: 1.45;
      }
      main {
        max-width: 680px;
      }
      h1 {
        font: -apple-system-title2;
        margin: 0 0 16px;
      }
      p {
        margin: 0 0 12px;
      }
      ul {
        margin: 0;
        padding-inline-start: 1.3em;
      }
      li {
        margin: 0 0 7px;
      }
    </style>
  </head>
  <body>
    <main>
      <h1>ExcalidrawZ #{CGI.escapeHTML(version)}</h1>
      #{body.join("\n      ")}
    </main>
  </body>
  </html>
  HTML
end

note_paths.each do |path|
  locale = File.basename(File.dirname(path))
  text = File.read(path, encoding: "UTF-8").strip
  next if text.empty?

  output_path = File.join(public_dir, "#{output_base_name}.#{locale}.html")
  FileUtils.mkdir_p(File.dirname(output_path))
  File.write(output_path, html_for_release_notes(version, locale, text))
  puts output_path
end
RUBY
}

generate_candidate_appcast() {
  section "Generate Candidate Appcast"
  "$GENERATE_APPCAST" \
    --download-url-prefix "$FEED_BASE_URL" \
    --release-notes-url-prefix "$FEED_BASE_URL" \
    --maximum-versions 1 \
    --maximum-deltas 0 \
    --link "https://excalidrawz.chocoford.com" \
    -o "$CANDIDATE_APPCAST" \
    "$SOURCE_WORK_DIR"

  require_file "$CANDIDATE_APPCAST" "candidate appcast"
}

rewrite_candidate_appcast_for_github() {
  /usr/bin/ruby - "$CANDIDATE_APPCAST" "$OUTPUT_PATH" "$REPO" "$FEED_BASE_URL" <<'RUBY'
require "cgi"
require "fileutils"
require "rexml/document"
require "uri"

candidate_appcast, output_path, repo, feed_base_url = ARGV
doc = REXML::Document.new(File.read(candidate_appcast))

def child(element, suffix)
  element.elements.each do |candidate|
    return candidate if candidate.name == suffix || candidate.expanded_name.end_with?(":#{suffix}")
  end
  nil
end

def child_text(element, suffix)
  child(element, suffix)&.text.to_s.strip
end

def encoded_filename(name)
  CGI.escape(name).gsub("+", "%20")
end

def github_release_asset_name(name)
  ext = File.extname(name)
  base = File.basename(name, ext)
  base = base.gsub(/[^\p{Alnum}._-]+/, ".")
  base = base.gsub(/\.+/, ".").sub(/\A\./, "").sub(/\.\z/, "")
  "#{base}#{ext}"
end

def remove_release_note_links(item)
  item.get_elements("sparkle:releaseNotesLink").each do |element|
    item.delete_element(element)
  end
end

def localized_release_note_links(public_dir, base_name, feed_base_url)
  localized_paths = Dir.glob(File.join(public_dir, "#{base_name}.*.html"))
  localized_paths.map do |path|
    locale = File.basename(path).sub(/\A#{Regexp.escape(base_name)}\./, "").sub(/\.html\z/, "")
    [locale, "#{feed_base_url.sub(%r{/*\z}, "")}/#{encoded_filename(File.basename(path))}"]
  end.sort_by do |locale, _url|
    locale == "en-US" ? ["", locale] : [locale, locale]
  end
end

channel = doc.root&.elements&.[]("channel") || abort("Candidate appcast has no channel")
items = channel.get_elements("item")
abort("Candidate appcast has no item") if items.empty?
public_dir = File.dirname(output_path)

items.each do |item|
  version = child_text(item, "shortVersionString")
  abort("Candidate appcast item is missing sparkle:shortVersionString") if version.empty?

  enclosure = item.elements["enclosure"] || abort("Candidate appcast item has no full enclosure")
  local_asset_name = URI.decode_www_form_component(File.basename(URI.parse(enclosure.attributes["url"].to_s).path))
  github_asset_name = github_release_asset_name(local_asset_name)
  github_release_notes_base = File.basename(github_asset_name, File.extname(github_asset_name))
  tag = "v#{version}"

  enclosure.attributes["url"] = "https://github.com/#{repo}/releases/download/#{tag}/#{encoded_filename(github_asset_name)}"
  remove_release_note_links(item)
  localized_release_note_links(public_dir, github_release_notes_base, feed_base_url).each do |locale, url|
    release_notes = REXML::Element.new("sparkle:releaseNotesLink")
    release_notes.add_attribute("xml:lang", locale)
    release_notes.text = url
    item.add_element(release_notes)
  end
end

FileUtils.mkdir_p(File.dirname(output_path))
File.write(output_path, doc.to_s)
File.open(output_path, "a") { |file| file.write("\n") }
RUBY
}

trap on_error ERR

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

REPO="chocoford/ExcalidrawZ"
ARCHIVES_DIR="$ROOT_DIR/archives-new"
PUBLIC_DIR="$ROOT_DIR/WebPage/public/downloads"
OUTPUT_PATH="$PUBLIC_DIR/appcast.xml"
GENERATE_APPCAST="$ROOT_DIR/scripts/Sparkle-2.6.4/bin/generate_appcast"
FASTLANE_METADATA_DIR="$ROOT_DIR/fastlane/metadata-mac"
FEED_BASE_URL="https://excalidrawz.chocoford.com/downloads/"
EXPECTED_VERSION=""
EXPECTED_ARCHIVE_PATH=""
VERIFY_GITHUB_ASSET=true

while [ "$#" -gt 0 ]; do
  case "$1" in
    --version)
      if [ "$#" -lt 2 ] || [ -z "$2" ]; then
        log "ERROR --version requires a value"
        exit 1
      fi
      EXPECTED_VERSION="$2"
      shift 2
      ;;
    --skip-github-asset-check)
      VERIFY_GITHUB_ASSET=false
      shift
      ;;
    --metadata-dir)
      if [ "$#" -lt 2 ] || [ -z "$2" ]; then
        log "ERROR --metadata-dir requires a value"
        exit 1
      fi
      FASTLANE_METADATA_DIR="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      log "ERROR Unknown argument: $1"
      usage
      exit 1
      ;;
  esac
done

section "Generate GitHub Appcast"
kv "repo" "$REPO"
kv "archives dir" "$ARCHIVES_DIR"
kv "public dir" "$PUBLIC_DIR"
kv "output" "$OUTPUT_PATH"
kv "release notes" "$FASTLANE_METADATA_DIR"
kv "feed base url" "$FEED_BASE_URL"
kv "expected version" "${EXPECTED_VERSION:-latest archive}"
kv "verify GitHub asset" "$VERIFY_GITHUB_ASSET"

if [ ! -x "$GENERATE_APPCAST" ]; then
  log "ERROR generate_appcast not found or not executable: $GENERATE_APPCAST"
  exit 1
fi

if [ ! -d "$ARCHIVES_DIR" ]; then
  log "ERROR archives directory does not exist: $ARCHIVES_DIR"
  exit 1
fi

if [ -n "$EXPECTED_VERSION" ]; then
  EXPECTED_ARCHIVE_PATH=$(find "$ARCHIVES_DIR" -maxdepth 1 -type f \
    \( -iname "*${EXPECTED_VERSION}*.dmg" -o -iname "*${EXPECTED_VERSION}*.zip" \) \
    -print -quit)

  if [ -z "$EXPECTED_ARCHIVE_PATH" ]; then
    log "ERROR no $EXPECTED_VERSION DMG or ZIP found in: $ARCHIVES_DIR"
    log "ERROR Add the final update archive before preparing the Sparkle manifest"
    exit 1
  fi

  kv "update archive" "$EXPECTED_ARCHIVE_PATH"
fi

if [ ! -d "$FASTLANE_METADATA_DIR" ]; then
  log "ERROR release notes directory does not exist: $FASTLANE_METADATA_DIR"
  exit 1
fi

release_note_count=$(find "$FASTLANE_METADATA_DIR" -mindepth 2 -maxdepth 2 -name release_notes.txt -type f | wc -l | tr -d ' ')
if [ "$release_note_count" -eq 0 ]; then
  log "ERROR no localized release notes found in: $FASTLANE_METADATA_DIR"
  exit 1
fi
kv "release note files" "$release_note_count"

TEMP_DIR="$(mktemp -d)"
SOURCE_WORK_DIR="$TEMP_DIR/source"
CANDIDATE_APPCAST="$TEMP_DIR/candidate-appcast.xml"
mkdir -p "$SOURCE_WORK_DIR"

cleanup() {
  rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

link_archive_files_to_work_dir
generate_candidate_appcast

section "Prepare GitHub Release Metadata"
candidate_count=0
RELEASE_NOTE_SOURCES=()
RELEASE_NOTE_DESTS=()
RELEASE_NOTE_VERSIONS=()
RELEASE_NOTE_BASE_NAMES=()
while IFS=$'\t' read -r BUILD VERSION ASSET_NAME; do
  [ -n "$BUILD" ] || continue

  if [ -n "$EXPECTED_VERSION" ] && [ "$VERSION" != "$EXPECTED_VERSION" ]; then
    log "ERROR Latest generated archive is version $VERSION, expected $EXPECTED_VERSION"
    log "ERROR Add the $EXPECTED_VERSION DMG to $ARCHIVES_DIR and try again"
    exit 1
  fi

  candidate_count=$((candidate_count + 1))

  TAG="v$VERSION"
  GITHUB_ASSET_NAME="$(github_release_asset_name "$ASSET_NAME")"
  ARCHIVE_PATH="$ARCHIVES_DIR/$ASSET_NAME"
  RELEASE_NOTES_PATH="${ARCHIVE_PATH%.*}.html"
  GITHUB_RELEASE_NOTES_NAME="${GITHUB_ASSET_NAME%.*}.html"
  GITHUB_RELEASE_NOTES_BASE="${GITHUB_ASSET_NAME%.*}"
  DOWNLOAD_URL_PREFIX="https://github.com/$REPO/releases/download/$TAG/"
  ASSET_URL="$DOWNLOAD_URL_PREFIX$(url_encode_filename "$GITHUB_ASSET_NAME")"

  kv "version" "$VERSION"
  kv "build" "$BUILD"
  kv "tag" "$TAG"
  kv "local asset" "$ASSET_NAME"
  kv "github asset" "$GITHUB_ASSET_NAME"
  kv "asset url" "$ASSET_URL"

  require_file "$ARCHIVE_PATH" "archive"
  if [ "$VERIFY_GITHUB_ASSET" = true ]; then
    verify_github_asset_uploaded "$ASSET_URL" "$TAG" "$GITHUB_ASSET_NAME"
    kv "asset reachable" "yes"
  else
    kv "asset reachable" "not checked"
  fi

  if [ -f "$RELEASE_NOTES_PATH" ]; then
    RELEASE_NOTE_SOURCES+=("$RELEASE_NOTES_PATH")
    RELEASE_NOTE_DESTS+=("$PUBLIC_DIR/$GITHUB_RELEASE_NOTES_NAME")
    kv "release notes" "$RELEASE_NOTES_PATH"
  else
    kv "release notes" "not found"
  fi

  RELEASE_NOTE_VERSIONS+=("$VERSION")
  RELEASE_NOTE_BASE_NAMES+=("$GITHUB_RELEASE_NOTES_BASE")
done < <(read_candidate_appcast_metadata "$CANDIDATE_APPCAST")

if [ "$candidate_count" -eq 0 ]; then
  log "ERROR Candidate appcast has no full update items"
  exit 1
fi

section "Clean Website Downloads"
clean_public_downloads

section "Copy Release Notes"
if [ -d "$FASTLANE_METADATA_DIR" ]; then
  for index in "${!RELEASE_NOTE_VERSIONS[@]}"; do
    while IFS= read -r generated_note; do
      [ -n "$generated_note" ] || continue
      kv "localized notes" "$generated_note"
    done < <(write_localized_release_notes "${RELEASE_NOTE_VERSIONS[$index]}" "${RELEASE_NOTE_BASE_NAMES[$index]}")
  done
elif [ "${#RELEASE_NOTE_SOURCES[@]}" -gt 0 ]; then
  for index in "${!RELEASE_NOTE_SOURCES[@]}"; do
    cp -p "${RELEASE_NOTE_SOURCES[$index]}" "${RELEASE_NOTE_DESTS[$index]}"
    kv "public notes" "${RELEASE_NOTE_DESTS[$index]}"
  done
else
  kv "release notes" "none"
fi

section "Write Website Appcast"
rewrite_candidate_appcast_for_github
kv "written" "$OUTPUT_PATH"

section "Generated Enclosures"
/usr/bin/perl -nE 'while (/enclosure\b[^>]*\burl=["'\'']([^"'\'']+)["'\'']/g) { say $1 }' "$OUTPUT_PATH" | while IFS= read -r url; do
  kv "enclosure" "$url"
done

section "Done"
