PLATFORM='linux'

function get_revision()
{
    pushd $1 >/dev/null
    echo $(git log -n 2 | tail -n1 | cut -f2 -d# | cut -f1 -d\})
    popd >/dev/null
}

function ensure-package() 
{
    local name="$1"
    local binary="${2:-$1}"
  #if ! which $binary > /dev/null 
  #then
    #sudo apt-get update -qq
    #sudo apt-get install -y $name
  #fi
}

function check_build_env() 
{
	local platform="$1"
	local target_cpu="$2"

	#if ! which sudo > /dev/null ; then
	#apt-get update -qq
	#apt-get install -y sudo
	#fi
	ensure-package curl
	ensure-package git
	ensure-package python
	ensure-package lbzip2
	ensure-package lsb-release lsb_release
}

function compile() 
{
  local platform="$1"
  local srcdir="$2"
  local outdir="$3"
  local target_os="$4"
  local target_cpu="$5"
  local configs="$6"
  local blacklist="$7"

  common_args='is_debug=true is_component_build=false rtc_use_h264=true use_rtti=true use_custom_libcxx=false treat_warnings_as_errors=false enable_libaom=true rtc_include_tests=false use_custom_libcxx_for_host=false rtc_include_pulse_audio=false is_clang=false'
  pushd $srcdir >/dev/null
  compile_ninja $outdir "$common_args $target_args"
  combine_static $platform $outdir libwebrtc
  popd >/dev/null
}

function compile_ninja() 
{
  local outdir="$1"
  local gn_args="$2"

  echo "Generating project files with: $gn_args"
  gn gen $outdir --args="$gn_args"
  echo "Building: $gn_args"
  echo '' >> $outdir/.ninja_log
  ninja -v -C $outdir
}

function combine_static() 
{
	local outdir="$2"
	local libname="$3"
	#out/src/out/x64	
	pushd $outdir >/dev/null
	rm -f $libname.*
	
	local whitelist="boringssl\.a|protobuf_full\.a|webrtc\.a|field_trial_default\.a|metrics_default\.a|task_queue_libevent\.o|default_task_queue_factory_libevent\.o"
	cat .ninja_log | tr '\t' '\n' | grep -E $whitelist | sort -u >$libname.list
	
	local LIST_OBJS=''
	local LIB_EVENT=$(cat .ninja_log | tr '\t' '\n' | grep -E libevent.a | tail -n1)
	local PEER_CONN_FACT=$(cat .ninja_log | tr '\t' '\n' | grep -E libcreate_peerconnection_factory.a | tail -n1)
	local WEBRTC_LIB=$(cat .ninja_log | tr '\t' '\n' | grep -E libwebrtc.a | tail -n1)
	echo "CREATE $libname.a" >$libname.ar
	echo "ADDLIB $LIB_EVENT" >>$libname.ar
	while read a 
	do
		if [[ ${a##*.} == 'o' ]]
		then
			LIST_OBJS="$a $LIST_OBJS"
		else
			echo "ADDLIB $a" >>$libname.ar
		fi
	done <$libname.list
	echo "ADDLIB $PEER_CONN_FACT" >>$libname.ar
	echo "SAVE" >>$libname.ar
	echo "END" >>$libname.ar
	ar -M < $libname.ar
	ranlib $libname.a
	
	FILE=$(ar t $PWD/${libname}.a|head -n1)
	for OBJ in $LIST_OBJS
	do
		ar rb $FILE $libname.a $OBJ
	done
	
	#g++ -std=c++14 -fPIC -shared -o $libname.so $libname.a
	mv $libname.a  "$(dirname $WEBRTC_LIB)"
	#mv $libname.so  "$(dirname $WEBRTC_LIB)"
	#rm  $WEBRTC_LIB
	#rm $libname.a
	rm $libname.ar
	popd >/dev/null
}

function package_prepare() 
{
	local srcdir="$1"
	local outdir="$2"
	local cpu="$3"
	local package_filename="$4"
	local resource_dir="$5"
	local configs="$6"

    local packagedir=$outdir/

    echo "Package preparing..."
	#out	
	pushd $srcdir >/dev/null
	
	# Create directory structure
	mkdir -p $package_filename/include
	#out/src
	# Copy header files, skip third_party dir
	find  -path 'third_party' -prune -o -type f -name '*.h' -print | xargs -I '{}' cp --parents '{}' $package_filename/include
	  
	find  \( -name '*.h' -o -name README -o -name LICENSE -o -name COPYING \) | grep './third_party' | \
		grep -E 'boringssl|expat/files|jsoncpp/source/json|libjpeg|libjpeg_turbo|libsrtp|libyuv|libvpx|opus|protobuf|usrsctp/usrsctpout/usrsctpout|abseil-cpp/absl' | \
		xargs -I '{}' cp --parents '{}' $package_filename/include
	
	mkdir -p $package_filename/lib/$TARGET_CPU
	find . \( -name '*.so' -o -name '*.a' \) | \
	#grep -E '.*webrtc.(a|so).*' |xargs -I '{}' cp '{}' $outdir/$package_filename/lib/$TARGET_CPU
	grep -E 'webrtc' |xargs -I '{}' cp '{}' $package_filename/lib/$TARGET_CPU
	popd >/dev/null
	
	echo "Package prepared completed"
}

function package_debian() 
{
	local srcdir="$1"
	local outdir="$2"
	local package_name="$3"
	local package_version="$4"
	local arch="$5"
	
	local package_filename="${package_name}"
	local debianize="$outdir/debianize/$package_filename"
	
	echo "Debianize WebRTC"
	local PRERM="$PWD/prerm"
	local POSTINST="$PWD/postinst"
	local PKG_CONFIG_IN="$PWD/resource/pkgconfig/libwebrtc.pc.in"
	
	pushd $srcdir >/dev/null
	mkdir -p $debianize/DEBIAN
	mkdir -p $debianize/opt
	mkdir -p $debianize/usr/share/pkgconfig
	WEBRTC_LOCAL=$WEBRTC_LOCAL envsubst < $PKG_CONFIG_IN > $debianize/usr/share/pkgconfig/libwebrtc.pc
	mv $package_name ${debianize}$WEBRTC_LOCAL
	cat << EOF > $debianize/DEBIAN/control
Package: $package_name
Architecture: $arch
Maintainer: Sourcey
Depends: debconf (>= 0.5.00)
Priority: optional
Version: $package_version
Description: webrtc static library
 This package provides webrtc library generated with webrtcbuilds
EOF
	TARGET_CPU=$TARGET_CPU envsubst < $POSTINST > $debianize/DEBIAN/postinst
	chmod 775 $debianize/DEBIAN/postinst
	cp "$PRERM" $debianize/DEBIAN
	pushd $debianize >/dev/null
	find opt -type f | sort | xargs -n1 md5sum > DEBIAN/md5sums
	popd >/dev/null
	fakeroot dpkg-deb --build $debianize
	mv $outdir/debianize/*.deb $outdir/
	rm -rf $outdir/debianize
	popd >/dev/null
}
