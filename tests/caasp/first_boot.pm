# SUSE's openQA tests
#
# Copyright © 2016-2018 SUSE LLC
#
# Copying and distribution of this file, with or without modification,
# are permitted in any medium without royalty provided the copyright
# notice and this notice are preserved.  This file is offered as-is,
# without any warranty.

# Summary: First boot and login into CaaSP
# Maintainer: Martin Kravec <mkravec@suse.com>

use base "opensusebasetest";
use strict;
use testapi;
use utils qw(power_action systemctl);
use version_utils 'is_caasp';
use bootloader_setup 'set_framebuffer_resolution';
use caasp 'process_reboot';

sub run {
    # On VMX images bootloader_uefi eats grub2 needle
    # On DVD images stall prevents reliable matching of BIOS needle - poo#28648
    if (is_caasp('DVD') && !get_var('AUTOYAST')) {
        assert_screen 'grub2';
    }

    # Check ssh keys & ip information are displayed
    assert_screen 'linux-login-casp', 300;

    # Workers installed using autoyast have no password - bsc#1030876
    return if get_var('AUTOYAST');

    # Login is displayed before cloud-init finishes - bsc#1035968
    if (is_caasp 'VMX') {
        # FreeRDP is not sending 'Ctrl' as part of 'Ctrl-Alt-Fx', 'Alt-Fx' is fine though.
        my $key = check_var('VIRSH_VMM_FAMILY', 'hyperv') ? 'alt-f2' : 'ctrl-alt-f2';
        send_key_until_needlematch 'tty2-selected', $key, 10, 30;
    }
    select_console 'root-console';

    # On Hyper-V we need to add special framebuffer provisions
    if (check_var('VIRSH_VMM_FAMILY', 'hyperv') || check_var('VIRSH_VMM_TYPE', 'linux')) {
        set_framebuffer_resolution;
        assert_script_run 'transactional-update grub.cfg';
        process_reboot 1;
    }

    # Restart network to push hostname to dns
    if (is_caasp('VMX') && get_var('STACK_ROLE')) {
        systemctl 'restart network', timeout => 60;
    }
}

sub test_flags {
    return {fatal => 1};
}

1;

# vim: set sw=4 et:
