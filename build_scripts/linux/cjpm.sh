set -e
set -o xtrace
. $(dirname $0)/init_env.sh

. $(dirname $0)/envsetup.sh

# cjpm
cd $WORKSPACE/cangjie_tools/cjpm/build;
[ "$SKIP_CLEAN" -eq 1 ] || python3 build.py clean;
bash $WORKSPACE/build_scripts/linux/clone_thirdparty.sh
if [ "$BUNDLE_WITH_LINKS" -eq 1 ]; then
    CJPM_RPATH="\$ORIGIN/../../../software/cangjie/runtime/lib/linux_${ARCH}_cjnative"
else
    CJPM_RPATH="\$ORIGIN/../../runtime/lib/linux_${ARCH}_cjnative"
fi
python3 build.py build -t "$CJPM_TARGET" --set-rpath "$CJPM_RPATH";
python3 build.py install;
