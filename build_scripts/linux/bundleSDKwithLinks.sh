set -o xtrace
. $(dirname $0)/init_env.sh

link_tree() {
    local src="$1"
    local dst="$2"
    local skip_cj="${3:-0}"

    rm -rf "$dst"
    mkdir -p "$dst"

    (cd "$src" && find . -type d -print) | while IFS= read -r path; do
        mkdir -p "$dst/$path"
    done

    (cd "$src" && find . ! -type d -print) | while IFS= read -r path; do
        if [ "$skip_cj" = "1" ]; then
            case "$path" in
                *.cj) continue ;;
            esac
        fi
        rm -f "$dst/$path"
        ln -s "$src/$path" "$dst/$path"
    done
}

link_files() {
    local dst="$1"
    shift

    mkdir -p "$dst"
    for src in "$@"; do
        [ -e "$src" ] || continue
        rm -f "$dst/$(basename "$src")"
        ln -sf "$(realpath "$src")" "$dst/$(basename "$src")"
    done
}

link_file_as() {
    local src="$1"
    local dst="$2"

    mkdir -p "$(dirname "$dst")"
    rm -f "$dst"
    ln -sf "$(realpath "$src")" "$dst"
}

materialize_file_if_link() {
    local path="$1"
    local target

    if [ -L "$path" ]; then
        target=$(realpath "$path")
        rm -f "$path"
        cp -p "$target" "$path"
    fi
}

# Bundle SDK
mkdir -p "$WORKSPACE/software";
rm -rf "$WORKSPACE"/software/*;
cd "$WORKSPACE/software";

# Link cangjie directory contents.
link_tree "$WORKSPACE/cangjie_compiler/output" cangjie;

# Remove ast-support.a.
rm -rf cangjie/lib/linux_${ARCH}_cjnative/libcangjie-ast-support.a

# Arrange files.
mkdir -p cangjie/tools/bin;
link_files cangjie/tools/bin "$WORKSPACE/cangjie_tools/cjpm/dist/cjpm";
mkdir -p cangjie/tools/config;
link_files cangjie/tools/bin "$WORKSPACE/cangjie_tools/cjfmt/build/build/bin/cjfmt";
link_files cangjie/tools/config "$WORKSPACE"/cangjie_tools/cjfmt/config/*.toml;
link_file_as "$WORKSPACE/cangjie_tools/hyperlangExtension/target/bin/main" cangjie/tools/bin/hle;
link_tree "$WORKSPACE/cangjie_tools/hyperlangExtension/src/dtsparser" cangjie/tools/dtsparser 1;
link_files cangjie/tools/bin "$WORKSPACE/cangjie_tools/cangjie-language-server/output/bin/LSPServer";

# Then link stdx artifacts.
link_tree "$WORKSPACE/cangjie_stdx/target" cangjie/stdx
# Keep envsetup local because appending through a symlink would modify compiler output.
materialize_file_if_link cangjie/envsetup.sh
echo 'export CANGJIE_STDX_PATH=${CANGJIE_HOME}/stdx' >> cangjie/envsetup.sh
echo 'export LD_LIBRARY_PATH=${CANGJIE_HOME}/linux_${ARCH}_cjnative/dynamic/stdx:${LD_LIBRARY_PATH}' >> cangjie/envsetup.sh
link_files cangjie/runtime/lib/linux_${ARCH}_cjnative cangjie/stdx/linux_${ARCH}_cjnative/dynamic/stdx/*.so
link_files cangjie/runtime/lib/linux_${ARCH}_cjnative cangjie/stdx/linux_${ARCH}_cjnative/dynamic/stdx/libstdx.syntaxFFI.a
link_files cangjie/lib/linux_${ARCH}_cjnative cangjie/stdx/linux_${ARCH}_cjnative/static/stdx/*.a
mkdir -p cangjie/modules/linux_${ARCH}_cjnative/stdx/;
link_files cangjie/modules/linux_${ARCH}_cjnative/stdx cangjie/stdx/linux_${ARCH}_cjnative/dynamic/stdx/*.cjo
link_files cangjie/modules/linux_${ARCH}_cjnative cangjie/stdx/linux_${ARCH}_cjnative/dynamic/stdx/stdx.cjo

# Package and set permissions.
find cangjie -type d -exec chmod 750 {} +
tar --format=gnu -zcvf cangjie-sdk-${SDK_NAME}-${CANGJIE_VERSION}.tar.gz cangjie;
chmod 550 cangjie-sdk-${SDK_NAME}-${CANGJIE_VERSION}.tar.gz;
