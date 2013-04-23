#! /bin/sh

RPM=http://packages.couchbase.com/releases/1.8.1/couchbase-server-enterprise_x86_64_1.8.1.rpm
HOTFIX=http://packages.couchbase.com/releases/1.8.1-HOTFIX-MB-5343-5624-6550/couchbase-server-1.8.1_HOTFIX-MB-5343-MB-5624-MB-6550.zip

set -e  # Fail on error

die () { echo "$0: FATAL ERROR: " "$@" >&2; exit 2; }

work_dir=$HOME/hotfix-couchbase
[ -d "$work_dir" ] || mkdir -p "$work_dir"
echo "Working directory is '$work_dir'"

cd "$work_dir"

echo "Getting sources"

get_file () {
    md5="$1"
    url="$2"
    b=`basename "$url"`
    echo "$md5  $b" > "$work_dir/$b.md5"
    md5sum -c "$work_dir/$b.md5" > /dev/null 2>&1 || wget "$url"
    # Re-verify after download
    md5sum -c "$work_dir/$b.md5"
}

get_file 487885ce486f044a700738ab8bb443ec "$RPM"
# See http://support.couchbase.com/entries/21374979-TAP-disconnect-causes-memory-leak-in-1-8-x-MB-6550-
get_file b2cf96bd47a130ae7e7ceb7f5697500a "$HOTFIX"

e=3 # Status 3 is normal for "not running"
if [ -x /etc/init.d/couchbase-server ]; then
    /etc/init.d/couchbase-server status || e=$?
fi

if [ $e -eq 0 ]; then
    echo "Shutting down Couchbase service"
    sudo /etc/init.d/couchbase-server stop
elif [ $e -ne 3 ]; then
    die "Got exit code $e checking coucbhase-server status"
fi

# Ensure memcached, moxi & beam.smp aren't running....
times=6
while pgrep -xl memcached || pgrep -xl beam.smp || pgrep -xl moxi; do
    times=$((times - 1))
    if [ $times -eq 0 ]; then
        die "Gave up waiting for Couchbase processes to exit. Kill them manually or wait longer, then retry."
    fi
    echo "Waiting for Couchbase proceses to exit...." >&2
    sleep 1
done


# Don't try to be clever here, it's ad-hoc solution
hf="$work_dir/HOTFIX-MB-5343-MB-5624-MB-6550/bin/centos-64"
if [ ! -d "$hf" ]; then
    echo "Unpacking hotfix..."
    (
        unzip couchbase-server-1.8.1_HOTFIX-MB-5343-MB-5624-MB-6550.zip
        cd HOTFIX-MB-5343-MB-5624-MB-6550
        unzip bin.zip
        cd bin
        unzip centos-64.zip
    )
fi

echo "Installing main Couchbase package"
# Use --replacepkgs in case we're already at desired version
sudo INSTALL_DONT_START_SERVER=1 rpm -Uvh --replacepkgs "$work_dir"/couchbase-server-enterprise_x86_64_1.8.1.rpm

copy_hf_file () {
    src="$1"
    tgt="$2"
    should_chk="$3"
    tgt_dir=`dirname "$tgt"`

    [ -r "$hf/$src" ] || die "Hotfix doesn't contain file $src (in $hf)?"
    chk=$(md5sum "$hf/$src" | cut -d' ' -f1)
    [ "$chk" = "$should_chk" ] || die "Checksum for '$hf/$src', '$chk', doesn't match expected '$should_chk'"

    [ -r "$tgt" ] || die "Target file to patch doesn't exist (at '$tgt')?"
    chk=$(md5sum "$tgt" | cut -d' ' -f1)
    echo "Backing up '$tgt' (checksum $chk)"
    sudo cp -v "$tgt" "$tgt.$chk"

    echo "Copying hotfix to '$tgt'"
    sudo cp -v "$hf/HOTFIX-MB-5343-MB-5624-MB-6550.txt" "$tgt_dir"/.
    sudo cp -v "$hf/$src" "$tgt"
    # Owner bin:bin is for Centos
    sudo chown bin:bin "$tgt"
    # Correct for current hotfix, perhaps future hotfix may have files w/ other perms
    sudo chmod 755 "$tgt"
}

copy_hf_file memcached /opt/couchbase/bin/memcached 30705e3d9db9fcb829f94ec1469697d7
copy_hf_file ep.so /opt/couchbase/lib/memcached/ep.so.0.0.0 88a1936beda23de69b08da2eacb3637b

echo "Hotfix installed. Starting up Couchbase Server."
sudo /etc/init.d/couchbase-server start
