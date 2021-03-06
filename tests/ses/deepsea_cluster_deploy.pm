# SUSE's openQA tests
#
# Copyright © 2018 SUSE LLC
#
# Copying and distribution of this file, with or without modification,
# are permitted in any medium without royalty provided the copyright
# notice and this notice are preserved.  This file is offered as-is,
# without any warranty.

# Summary: Deploy ceph cluster http://docserv.suse.de/documents/Storage_5/ses-deployment/single-html/
# Maintainer: Jozef Pupava <jpupava@suse.cz>

use base 'opensusebasetest';
use strict;
use testapi;
use lockapi;
use utils qw(zypper_call systemctl);

sub run {
    zypper_call 'up';
    if (check_var('HOSTNAME', 'master')) {
        my $num_nodes = get_var('NODE_COUNT');
        barrier_create('salt_master_ready',      $num_nodes + 1);
        barrier_create('salt_minions_connected', $num_nodes + 1);
        zypper_call 'in deepsea ceph openattic';
        assert_script_run 'echo "deepsea_minions: \'*\'" > /srv/pillar/ceph/deepsea_minions.sls';
        systemctl 'start salt-master';
        systemctl 'enable salt-master';
        systemctl 'status salt-master';
        barrier_wait {name => 'salt_master_ready', check_dead_job => 1};
        assert_script_run 'sed -i \'s/#master: salt/master: master/\' /etc/salt/minion';
        systemctl 'start salt-minion';
        systemctl 'enable salt-minion';
        systemctl 'status salt-minion';
        # wait until all minions are started and accept minion keys
        barrier_wait {name => 'salt_minions_connected', check_dead_job => 1};
        assert_script_run 'salt-key --accept-all --yes';
        # salt does not return 1 if any node will fail ping test
        assert_script_run 'for i in {1..7}; do echo "try $i" && if [[ $(salt \'*\' test.ping |& tee ping.log) = *"Not connected"* ]];
 then cat ping.log && false; else salt \'*\' test.ping && break; fi; done';
        assert_script_run 'salt \'*\' cmd.run \'lsblk\'';
        assert_script_run 'deepsea stage run ceph.stage.0', 1200;
        assert_script_run 'deepsea stage run ceph.stage.1', 1200;
        my $policy = get_var('SES_POLICY');
        assert_script_run 'wget ' . data_url("ses/$policy");
        assert_script_run "mv $policy /srv/pillar/ceph/proposals/policy.cfg";
        assert_script_run 'cat /srv/pillar/ceph/proposals/policy.cfg';
        assert_script_run 'deepsea stage run ceph.stage.2', 1200;
        assert_script_run 'deepsea stage run ceph.stage.3', 1200;
        assert_script_run 'ceph osd df tree';
        assert_script_run 'ceph -s';
        barrier_wait {name => 'deployment_done', check_dead_job => 1};
    }
    else {
        barrier_wait('salt_master_ready');
        zypper_call 'in salt-minion ceph';
        # set master node as salt-master
        assert_script_run 'sed -i \'s/#master: salt/master: master/\' /etc/salt/minion';
        systemctl 'start salt-minion';
        systemctl 'enable salt-minion';
        systemctl 'status salt-minion';
        # wait until all minions are started and master will continue with deployment
        barrier_wait {name => 'salt_minions_connected'};
        # all nodes have to run until master finishes cluster deployment
        barrier_wait {name => 'deployment_done'};
    }
}

sub test_flags {
    return {fatal => 1};
}

1;

# vim: set sw=4 et:
