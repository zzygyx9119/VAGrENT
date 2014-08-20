#!/bin/bash

SOURCE_SAMTOOLS="https://github.com/samtools/samtools/archive/0.1.20.tar.gz"
SOURCE_TABIX="http://sourceforge.net/projects/samtools/files/tabix/tabix-0.2.6.tar.bz2/download"

done_message () {
    if [ $? -eq 0 ]; then
        echo " done."
        if [ "x$1" != "x" ]; then
            echo $1
        fi
    else
        echo " failed.  See setup.log file for error messages." $2
        echo "    Please check INSTALL file for items that should be installed by a package manager"
        exit 1
    fi
}

get_distro () {
  EXT=""
  DECOMP="gunzip -f"
  if [[ $2 == *.tar.bz2* ]] ; then
    EXT="tar.bz2"
    DECOMP="bzip2 -fd"
  elif [[ $2 == *.tar.gz* ]] ; then
    EXT="tar.gz"
  else
    echo "I don't understand the file type for $1"
    exit 1
  fi
  if hash curl 2>/dev/null; then
    curl -sS -o $1.$EXT -L $2
  else
    wget -nv -O $1.$EXT $2
  fi
  mkdir -p $1
  `$DECOMP $1.$EXT`
  tar --strip-components 1 -C $1 -xf $1.tar
}

if [ "$#" -ne "1" ] ; then
  echo "Please provide an installation path  such as /opt/ICGC"
  exit 0
fi

CPU=`cat /proc/cpuinfo | egrep "^processor" | wc -l`
echo "Max compilation CPUs set to $CPU"

INST_PATH=$1

# get current directory
INIT_DIR=`pwd`

# cleanup inst_path
mkdir -p $INST_PATH/bin
cd $INST_PATH
INST_PATH=`pwd`
cd $INIT_DIR

# make sure that build is self contained
unset PERL5LIB
ARCHNAME=`perl -e 'use Config; print $Config{archname};'`
PERLROOT=$INST_PATH/lib/perl5
PERLARCH=$PERLROOT/$ARCHNAME
export PERL5LIB="$PERLROOT:$PERLARCH"

#create a location to build dependencies
SETUP_DIR=$INIT_DIR/install_tmp
mkdir -p $SETUP_DIR

# re-initialise log file
echo > $INIT_DIR/setup.log


# log information about this system
(
    echo '============== System information ===='
    set -x
    lsb_release -a
    uname -a
    sw_vers
    system_profiler
    grep MemTotal /proc/meminfo
    set +x
    echo
) >>$INIT_DIR/setup.log 2>&1

echo -n "Building tabix ..."
if [ -e $SETUP_DIR/tabix.success ]; then
  echo -n " previously installed ..."
else
  (
    cd $SETUP_DIR
    set -ex
    get_distro tabix $SOURCE_TABIX
    cd $SETUP_DIR/tabix
    make -j$CPU
    cp tabix $INST_PATH/bin/.
    cp bgzip $INST_PATH/bin/.
    cd perl
    patch Makefile.PL < $INIT_DIR/patches/tabixPerlLinker.diff
    perl Makefile.PL INSTALL_BASE=$INST_PATH
    make
    make test
    make install
    touch $SETUP_DIR/tabix.success
  ) >>$INIT_DIR/setup.log 2>&1
fi
done_message "" "Failed to build tabix."

# need to build samtools as has to be compiled in correct way for perl bindings
# does not deploy binary in this form
echo -n "Building samtools ..."
if [ -e $SETUP_DIR/samtools.success ]; then
  echo -n " previously installed ...";
else
  cd $SETUP_DIR
  (
  set -x
  if [ ! -e samtools ]; then
    get_distro "samtools" $SOURCE_SAMTOOLS
    perl -i -pe 's/^CFLAGS=\s*/CFLAGS=-fPIC / unless /\b-fPIC\b/' samtools/Makefile
  fi
  make -C samtools -j$CPU
  touch $SETUP_DIR/samtools.success
  )>>$INIT_DIR/setup.log 2>&1
fi
done_message "" "Failed to build samtools."

export SAMTOOLS="$SETUP_DIR/samtools"

#add bin path for PCAP install tests
export PATH="$INST_PATH/bin:$PATH"

cd $INIT_DIR

echo -n "Installing Perl prerequisites ..."
if ! ( perl -MExtUtils::MakeMaker -e 1 >/dev/null 2>&1); then
    echo
    echo "WARNING: Your Perl installation does not seem to include a complete set of core modules.  Attempting to cope with this, but if installation fails please make sure that at least ExtUtils::MakeMaker is installed.  For most users, the best way to do this is to use your system's package manager: apt, yum, fink, homebrew, or similar."
fi
(
  set -x
  perl $INIT_DIR/bin/cpanm -v --mirror http://cpan.metacpan.org --notest -l $INST_PATH/ --installdeps . < /dev/null
  set +x
) >>$INIT_DIR/setup.log 2>&1
done_message "" "Failed during installation of core dependencies."

echo -n "Installing vagrent ..."
(
  set -e
  cd $INIT_DIR
  perl Makefile.PL INSTALL_BASE=$INST_PATH
  make
  make test
  make install
) >>$INIT_DIR/setup.log 2>&1
done_message "" "vagrent install failed."

# cleanup all junk
rm -rf $SETUP_DIR



echo
echo
echo "Please add the following to beginning of path:"
echo "  $INST_PATH/bin"
echo "Please add the following to beginning of PERL5LIB:"
echo "  $PERLROOT"
echo "  $PERLARCH"
echo