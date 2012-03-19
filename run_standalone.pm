#!/usr/bin/perl -w

use VCL::Module::Provisioning::tmrk;
use Term::ReadKey;

print "Terremark vCloud Express API client\n";

print "Username: ";
my $username = ReadLine(0);
chomp $username;

print "Password: ";
ReadMode('noecho');
my $password = ReadLine(0);
chomp $password;
ReadMode('normal');
print "\n";

my $default_identity_file = $ENV{"HOME"}."/.ssh/vcloud.pem";
print "Identity file [$default_identity_file]: ";
my $identity_file = ReadLine(0);
chomp $identity_file;
if (!$identity_file) {
	$identity_file = $default_identity_file;
}
if ( ! -e $identity_file ) {
    print "Not found: $identity_file\n" ;
    exit 1;
}
my @identity_files = ($identity_file);

print "Name of VM to create: ";
my $vm_name = ReadLine(0);
chomp $vm_name;

$tmrk = VCL::Module::Provisioning::tmrk->new(username => $username, password => $password, identity_files => \@identity_files);
$tmrk->initialize();

#$tmrk->versions();

$tmrk->load(vAppName => $vm_name);
