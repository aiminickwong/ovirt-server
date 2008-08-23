install

%include common-install.ks

network --device=eth1 --bootproto=static --ip=192.168.50.2 --netmask=255.255.255.0 --onboot=on --nameserver=192.168.50.2 --hostname=management.priv.ovirt.org

%include repos.ks

%packages --nobase

%include common-pkgs.ks

%post
exec > /root/kickstart-post.log 2>&1

%include common-post.ks

# FIXME [PATCH] fix SelinuxConfig firewall side-effect
lokkit -f --nostart --disabled
# FIXME imgcreate.kickstart.NetworkConfig doesn't store nameserver into ifcfg-*
#       only in resolv.conf which gets overwritten by dhclient-script
augtool <<EOF
set /files/etc/sysconfig/network-scripts/ifcfg-eth0/PEERDNS no
set /files/etc/sysconfig/network-scripts/ifcfg-eth1/DNS1 192.168.50.2
save
EOF

# make sure to update the /etc/hosts with the list of all possible DHCP
# addresses we can hand out; dnsmasq uses this
sed -i -e 's/management\.priv\.ovirt\.org//' /etc/hosts
echo "192.168.50.2 management.priv.ovirt.org" >> /etc/hosts
for i in `seq 3 252` ; do
    echo "192.168.50.$i node$i.priv.ovirt.org" >> /etc/hosts
done

# Enable forwarding so this node can act as a router for the .50 network
sed -i 's/net.ipv4.ip_forward = .*/net.ipv4.ip_forward = 1/' /etc/sysctl.conf
cat > /etc/sysconfig/iptables << EOF
*nat
-A POSTROUTING -o eth0 -j MASQUERADE
COMMIT
EOF

# Create sparse files for iSCSI backing stores
mkdir -p /ovirtiscsi
for i in `seq 3 5`; do
    dd if=/dev/null of=/ovirtiscsi/iSCSI$i bs=1 count=1 seek=3G
done

# make an NFS directory with some small, fake disks and export them via NFS
# to show off the NFS part of the WUI
mkdir -p /ovirtnfs
for i in `seq 1 3`; do
    dd if=/dev/zero of=/ovirtnfs/disk$i.dsk bs=1 count=1 seek=3G
done
echo "/ovirtnfs 192.168.50.0/24(rw,no_root_squash)" >> /etc/exports

# make collectd.conf.
cat > /etc/collectd.conf << \EOF
LoadPlugin network
LoadPlugin logfile
LoadPlugin rrdtool
LoadPlugin unixsock

<Plugin logfile>
        LogLevel info
        File STDOUT
</Plugin>

<Plugin network>
        Listen "0.0.0.0"
</Plugin>

<Plugin rrdtool>
        DataDir "/var/lib/collectd/rrd"
        CacheTimeout 120
        CacheFlush   900
</Plugin>

<Plugin unixsock>
        SocketFile "/var/lib/collectd/unixsock"
</Plugin>

EOF


principal=ovirtadmin
password=ovirt
first_run_file=/etc/init.d/ovirt-wui-dev-first-run
sed -e "s,@principal@,$principal," \
    -e "s,@password@,$password,g" \
   > $first_run_file << \EOF
#!/bin/bash
#
# ovirt-wui-dev-first-run First run configuration for oVirt WUI Dev appliance
#
# chkconfig: 3 95 01
# description: ovirt wui dev appliance first run configuration
#

# Source functions library
. /etc/init.d/functions

export PATH=/usr/kerberos/bin:$PATH

start() {
	echo -n "Starting ovirt-wui-dev-first-run: "
	(
	# workaround for https://bugzilla.redhat.com/show_bug.cgi?id=451936
	sed -i '/\[kdcdefaults\]/a \ kdc_ports = 88' /usr/share/ipa/kdc.conf.template
	# set up freeipa
	ipa-server-install -r PRIV.OVIRT.ORG -p @password@ -P @password@ -a @password@ \
	  --hostname management.priv.ovirt.org -u dirsrv -U

        # workaround for https://bugzilla.redhat.com/show_bug.cgi?id=459061
        # note: this has to happen after ipa-server-install or the templating
	# feature in ipa-server-install chokes on the characters in the regexp
	# we add here.
        sed -i -e 's#<Proxy \*>#<ProxyMatch ^.*/ipa/ui.*$>#' \
          /etc/httpd/conf.d/ipa.conf
        sed -i -e 's#</Proxy>#</ProxyMatch>#' /etc/httpd/conf.d/ipa.conf
        # workaround for https://bugzilla.redhat.com/show_bug.cgi?id=459209
        sed -i -e 's/^/#/' /etc/httpd/conf.d/ipa-rewrite.conf
	service httpd restart
	# now create the ovirtadmin user
	echo @password@|kinit admin
	# change max username length policy
	ldapmodify -h management.priv.ovirt.org -p 389 -Y GSSAPI <<LDAP
dn: cn=ipaConfig,cn=etc,dc=priv,dc=ovirt,dc=org
changetype: modify
replace: ipaMaxUsernameLength
ipaMaxUsernameLength: 12
LDAP
	ipa-adduser -f Ovirt -l Admin -p @password@ @principal@
	# make ovitadmin also an IPA admin
	ipa-modgroup -a ovirtadmin admins
	ipa-moduser --setattr krbPasswordExpiration=19700101000000Z @principal@

	) > /var/log/ovirt-wui-dev-first-run.log 2>&1
	RETVAL=$?
	if [ $RETVAL -eq 0 ]; then
		echo_success
	else
		echo_failure
	fi
	echo
}

case "$1" in
  start)
        start
        ;;
  *)
        echo "Usage: ovirt-wui-dev-first-run {start}"
        exit 2
esac

chkconfig ovirt-wui-dev-first-run off
EOF
chmod +x $first_run_file
chkconfig ovirt-wui-dev-first-run on

cat > /etc/init.d/ovirt-wui-dev << \EOF
#!/bin/bash
#
# ovirt-wui-dev oVirt WUI Dev appliance service
#
# chkconfig: 3 60 40
# description: ovirt wui dev appliance service
#

# Source functions library
. /etc/init.d/functions

start() {
    echo -n "Starting ovirt-wui-dev: "
    dnsmasq -i eth1 -F 192.168.50.6,192.168.50.252 \
        -G 00:16:3e:12:34:57,192.168.50.3 -G 00:16:3e:12:34:58,192.168.50.4 \
        -G 00:16:3e:12:34:59,192.168.50.5 \
        -s priv.ovirt.org \
        -W _ovirt._tcp,management.priv.ovirt.org,80 \
        -W _ipa._tcp,management.priv.ovirt.org,80 \
        -W _ldap._tcp,management.priv.ovirt.org,389 \
        -W _collectd._tcp,management.priv.ovirt.org,25826 \
        -W _identify._tcp,management.priv.ovirt.org,12120 \
        --enable-tftp --tftp-root=/var/lib/tftpboot -M pxelinux.0 \
        -O option:router,192.168.50.2 -O option:ntp-server,192.168.50.2 \
        --dhcp-option=12 \
        -R --local /priv.ovirt.org/ --server 192.168.122.1

    # Set up the fake iscsi target
    tgtadm --lld iscsi --op new --mode target --tid 1 \
        -T ovirtpriv:storage

    #
    # Now associate them to the backing stores
    #
    tgtadm --lld iscsi --op new --mode logicalunit --tid 1 \
        --lun 1 -b /ovirtiscsi/iSCSI3
    tgtadm --lld iscsi --op new --mode logicalunit --tid 1 \
        --lun 2 -b /ovirtiscsi/iSCSI4
    tgtadm --lld iscsi --op new --mode logicalunit --tid 1 \
        --lun 3 -b /ovirtiscsi/iSCSI5

    #
    # Now make them available
    #
    tgtadm --lld iscsi --op bind --mode target --tid 1 -I ALL

    echo_success
    echo
}

stop() {
    echo -n "Stopping ovirt-wui-dev: "

    # stop access to the iscsi target
    tgtadm --lld iscsi --op unbind --mode target --tid 1 -I ALL

    # unbind the LUNs
    tgtadm --lld iscsi --op delete --mode logicalunit --tid 1 --lun 3
    tgtadm --lld iscsi --op delete --mode logicalunit --tid 1 --lun 2
    tgtadm --lld iscsi --op delete --mode logicalunit --tid 1 --lun 1

    # shutdown the target
    tgtadm --lld iscsi --op delete --mode target --tid 1

    kill $(cat /var/run/dnsmasq.pid)

    echo_success
    echo
}

case "$1" in
    start)
        start
        ;;
    stop)
        stop
        ;;
    restart)
        stop
        start
        ;;
    *)
        echo "Usage: ovirt-wui-dev {start|stop|restart}"
        exit 2
esac
EOF
chmod +x /etc/init.d/ovirt-wui-dev
chkconfig ovirt-wui-dev on

%end

%post --nochroot
  # distribution tree is ready in tmp/tree
  set -e
  python -c '
from iniparse.ini import INIConfig
ini = INIConfig()
fp = open("tmp/tree/.treeinfo")
ini.readfp(fp)
fp.close()
family = ini.general.family
version = ini.general.version
arch = ini.general.arch
print "%s %s %s" % (family, version, arch)' | ( read os ver arch
      dest=$INSTALL_ROOT/var/www/cobbler/ks_mirror/$os-$ver-$arch
      printf "Importing $os-$ver-$arch ..."
      cp -a tmp/tree $dest
      url=http://download.fedoraproject.org/pub/fedora/linux
      cat >> $INSTALL_ROOT/etc/rc.d/rc.cobbler-import << EOF
#!/bin/sh
# Import Cobbler profiles on first boot

exec > /root/cobbler-import.log 2>&1

# run only once
chmod -x \$0
set -x

cobbler import --name=$os-$ver --arch=$arch \
  --path=/var/www/cobbler/ks_mirror/$os-$ver-$arch
cobbler repo add --name=f9-$arch --arch=$arch --mirror-locally=0 \
  --mirror=$url/releases/9/Everything/$arch/os
cobbler repo add --name=f9-$arch-updates --arch=$arch --mirror-locally=0 \
  --mirror=$url/updates/9/$arch
sed -e 's#^url .*#url --url=$url/releases/$ver/$os/$arch/os#' \
    -e 's#^reboot.*#poweroff#' /etc/cobbler/sample_end.ks \
    > /etc/cobbler/sample-$os-$ver-$arch.ks
cobbler profile edit --name=$os-$ver-$arch \
  --repos="f9-$arch f9-$arch-updates" \
  --kickstart=/etc/cobbler/sample-$os-$ver-$arch.ks

# TODO extract Node boot params from /var/lib/tftboot/pxelinux.cfg/default
# before Cobbler overwrites it
cobbler distro add --name="oVirt-Node-$arch" --arch=$arch \
  --initrd=/var/lib/tftpboot/initrd0.img --kernel=/var/lib/tftpboot/vmlinuz0 \
  --kopts="rootflags=loop root=/ovirt.iso rootfstype=iso9660 ro console=ttyS0,115200n8 console=tty0"
cobbler profile add --name=oVirt-Node-$arch --distro=oVirt-Node-$arch
cobbler system add --netboot-enabled=1 --profile=oVirt-Node-$arch \
  --name=node3 --mac=00:16:3e:12:34:57
cobbler system add --netboot-enabled=1 --profile=oVirt-Node-$arch \
  --name=node4 --mac=00:16:3e:12:34:58
cobbler system add --netboot-enabled=1 --profile=oVirt-Node-$arch \
  --name=node5 --mac=00:16:3e:12:34:59
set +x
echo "Add new oVirt Nodes as Cobbler systems to make them PXE boot oVirt Node image directly."
echo "oVirt-Node-$arch is also default boot option in Cobbler menu"
EOF
      chmod +x $INSTALL_ROOT/etc/rc.d/rc.cobbler-import
      echo "[ -x /etc/rc.d/rc.cobbler-import ] && /etc/rc.d/rc.cobbler-import" \
            >> $INSTALL_ROOT/etc/rc.d/rc.local
      printf "oVirt-Node-$arch" > $INSTALL_ROOT/tmp/cobbler-default
      echo done
  )
%end

# Cobbler configuration
%post
  exec >> /root/kickstart-post.log 2>&1
  # ovirt/ovirt
  echo ovirt:Cobbler:68db208a546dcedf34edf0b4fe0ab1f2 > /etc/cobbler/users.digest
  # make cobbler check happier
  mkdir -p /etc/vsftpd
  touch /etc/vsftpd/vsftpd.conf
  # TODO use Augeas 0.3.0 Inifile lens
  sed -i -e "s/^module = authn_denyall.*/module = authn_configfile/" \
      /etc/cobbler/modules.conf
  sed -i -e "s/^server:.*/server: '192.168.50.2'/" \
         -e "s/^next_server:.*/next_server: '192.168.50.2'/" \
      /etc/cobbler/settings
  sed -i -e '/kernel /a \\tIPAPPEND 2' /etc/cobbler/pxesystem.template
  sed -i -e "s/^ONTIMEOUT.*/ONTIMEOUT $(cat /tmp/cobbler-default)/" \
      /etc/cobbler/pxedefault.template
%end
