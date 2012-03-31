#!/usr/bin/perl -w
###############################################################################
# $Id: Linux.pm 795834 2009-07-20 13:37:52Z arkurth $
###############################################################################
# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with
# this work for additional information regarding copyright ownership.
# The ASF licenses this file to You under the Apache License, Version 2.0
# (the "License"); you may not use this file except in compliance with
# the License.  You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
###############################################################################

=head1 NAME

VCL::Module::OS::Linux::Linux_tmrk.pm - VCL module to support Linux on Terremark VMs

=head1 SYNOPSIS

 Needs to be written

=head1 DESCRIPTION

 This module provides VCL support for Linux operating systems on remote  
 Terremark virtual machines.

=cut

##############################################################################
package VCL::Module::OS::Linux::Linux_tmrk;

# Specify the lib path using FindBin
use FindBin;
use lib "$FindBin::Bin/../../../..";

# Configure inheritance
use base qw(VCL::Module::OS::Linux);

# Specify the version of this module
our $VERSION = '2.2.1';

# Specify the version of Perl to use
use 5.008000;

use strict;
use warnings;
use diagnostics;

use VCL::utils;

##############################################################################

=head1 OBJECT METHODS

=cut

#/////////////////////////////////////////////////////////////////////////////

=head2 update_public_ip_address

 Parameters  :
 Returns     :
 Description : 

=cut

sub update_public_ip_address {
	return 1;
}

#/////////////////////////////////////////////////////////////////////////////

=head2 reserve

 Parameters  :
 Returns     :
 Description : 

=cut

sub reserve {
	my $self = shift;
	if (ref($self) !~ /linux/i) {
		notify($ERRORS{'CRITICAL'}, 0, "subroutine was called as a function, it must be called as a class method");
		return 0;
	}
	
	$self->_pre_reserve;
	$self->SUPER::reserve;
	
	return 1;
}

#/////////////////////////////////////////////////////////////////////////////

=head2 _pre_reserve

 Parameters  :
 Returns     :
 Description : 

=cut

sub _pre_reserve {
	my $self = shift;
	if (ref($self) !~ /linux/i) {
		notify($ERRORS{'CRITICAL'}, 0, "subroutine was called as a function, it must be called as a class method");
		return 0;
	}
	
	my $computer_shortname   = $self->data->get_computer_short_name;
    my $management_node_keys = $self->data->get_management_node_keys();
    my $command;
    my $user = "vcloud";

    $command = "sudo mkdir -m 700 /root/.ssh";
    run_ssh_command($computer_shortname, $management_node_keys, $command, $user);
    
    $command = "sudo cp ~$user/.ssh/authorized_keys /root/.ssh/";
    if (run_ssh_command($computer_shortname, $management_node_keys, $command, $user)) {
		notify($ERRORS{'DEBUG'}, 0, "Setup root authorized_keys on $computer_shortname");
	}
	else {
		notify($ERRORS{'CRITICAL'}, 0, "Failed to setup root authorized_keys on $computer_shortname ");
		return;
	}
    
    $command = 'sudo sed -i s/"PermitRootLogin no"/"PermitRootLogin yes"/ /etc/ssh/sshd_config';
    if (run_ssh_command($computer_shortname, $management_node_keys, $command, $user)) {
		notify($ERRORS{'DEBUG'}, 0, "Enabled root login on $computer_shortname");
	}
	else {
		notify($ERRORS{'CRITICAL'}, 0, "Failed to enable root login on $computer_shortname ");
		return;
	}

    $command = 'sudo sed -i s/"PasswordAuthentication no"/"PasswordAuthentication yes"/ /etc/ssh/sshd_config';
    if (run_ssh_command($computer_shortname, $management_node_keys, $command, $user)) {
		notify($ERRORS{'DEBUG'}, 0, "Enabled password authentication on $computer_shortname");
	}
	else {
		notify($ERRORS{'CRITICAL'}, 0, "Failed to enable password authentication on $computer_shortname ");
		return;
	}

    $command = "sudo /etc/init.d/sshd restart";
    if (run_ssh_command($computer_shortname, $management_node_keys, $command, $user)) {
		notify($ERRORS{'DEBUG'}, 0, "Restarted sshd on $computer_shortname");
	}
	else {
		notify($ERRORS{'CRITICAL'}, 0, "Failed to restart sshd on $computer_shortname ");
		return;
	}

    # Write the details about the new image to ~/currentimage.txt
    if (!write_currentimage_txt($self->data)) {
        notify($ERRORS{'WARNING'}, 0, "failed to create the currentimage.txt file on the VM");
        return;
    }

	# Add a line to currentimage.txt indicating post_load has run
	$self->set_vcld_post_load_status();
	
	return 1;
}

#/////////////////////////////////////////////////////////////////////////////

=head2 grant_access

 Parameters  : called as an object
 Returns     : 1 - success , 0 - failure
 Description : 

=cut

sub grant_access {
	return 1;
} ## end sub grant_access


#/////////////////////////////////////////////////////////////////////////////

=head2 revoke_access

 Parameters  : called as an object
 Returns     : 1 - success , 0 - failure
 Description : 

=cut

sub revoke_access {
	return 1;
} ## end sub revoke_access


1;
__END__

=head1 SEE ALSO

L<http://cwiki.apache.org/VCL/>

=cut
