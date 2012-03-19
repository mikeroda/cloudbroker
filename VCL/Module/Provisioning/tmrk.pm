#!/usr/bin/perl -w
###############################################################################
# Mike Roda    mike@mikeroda.com
#
###############################################################################

=head1 NAME

VCL::Module::Provisioning::tmrk

=head1 SYNOPSIS

 VCL module to support Terremark vCloud Express v0.8 API Provisioning

=head1 DESCRIPTION

 This module provides support for Terremark vCloud Express API 0.8a-ext1.6
 http://vcloudexpress.terremark.com/
 API documentation:
 https://community.vcloudexpress.terremark.com/en-us/product_docs/m/vcefiles/2342/download.aspx

=cut

##############################################################################
package VCL::Module::Provisioning::tmrk;

our $VERSION = '0.1';

use strict;
use warnings;
use diagnostics;
use English qw( -no_match_vars );

use constant vCLOUD => 'https://services.vcloudexpress.terremark.com/api';
use constant vCLOUD_API => 'v0.8a-ext1.6';
use constant vCLOUD_RETRIES => 0;
use constant vCLOUD_IMAGE => 'CentOS 5 (32-bit)';
use constant vCLOUD_NS => 'http://www.vmware.com/vcloud/v0.8';
use constant TIMEOUT_DEPLOY_MINS => 10;
use constant TIMEOUT_POWER_ON_MINS => 5;
use constant TIMEOUT_POWER_OFF_MINS => 5;
use constant POLLING_INTERVAL_SECS => 20;
use constant use_intantiation_params => 0;

use HTTP::Request;
use HTTP::Request::Common;
use HTTP::Cookies;
use LWP::UserAgent;
use IO::Socket::SSL;
use XML::LibXML;
use Net::SSH::Perl;

our $verbose = 0;
our $cookie_jar;
our $ua;

#///////////////////////////////////////////////////////////////////////////// 
=head2 new
        
 Parameters  : username => '<username>', password => '<password>'
 Returns     : Terremark
 Description : Constructor for the Terremark package

=cut

sub new {
   my($class, %args) = @_;
 
   my $self = bless({}, $class);
 
   $self->{username} = $args{username};
   $self->{password} = $args{password};
   $self->{identity_files} = $args{identity_files};
 
   return $self;
}

#///////////////////////////////////////////////////////////////////////////// 
=head2 initialize
        
 Parameters  : none
 Returns     : boolean
 Description : Initialized the VMware vCloud API object by logging in and 
               obtaining a token for subsequent calls. False is returned if a
               token cannot be obtained. 

=cut

sub initialize {
    my $self = shift;
    unless (ref($self) && $self->isa('VCL::Module::Provisioning::tmrk')) {
        die "subroutine can only be called as a module object method";
    }
        
	$cookie_jar = HTTP::Cookies->new(
    file => "$ENV{'HOME'}/lwp_cookies.dat",
	    autosave => 1,
    	ignore_discard => 0,
	);

	$ua = LWP::UserAgent->new;
	$ua->cookie_jar($cookie_jar);

    my $response = $self->_login() || return 0;

	# get a link to the organization from the information returned from login
	my $org = $self->_xpath_wrap($response->content, '//ns:Org/@href');

	# get the organization information to obtain a link to the vDC
    my $req = HTTP::Request->new(GET => $org);
    $response = $self->_request($req);
	$self->{vDC} = $self->_xpath_wrap($response->content, '//ns:Link[@type=\'application/vnd.vmware.vcloud.vdc+xml\']/@href');

    return 1;
}       

#///////////////////////////////////////////////////////////////////////////// 
=head2 _barf
        
 Parameters  : HTTP::Request, HTTP::Response
 Returns     : none
 Description : A shortcut for outputting errors from the REST server

=cut

# A shortcut for outputting errors form the REST server
sub _barf {
    my $self = shift;
	my $req = shift;
    my $response = shift;
    
    unless (ref($self) && $self->isa('VCL::Module::Provisioning::tmrk')) {
        die "subroutine can only be called as a module object method";
    }
    
    my $message = $response->content;

	print "\n";
	print $req->as_string;
	print "\n\n";
    die "$message";
}

#///////////////////////////////////////////////////////////////////////////// 
=head2 _login
        
 Parameters  : none
 Returns     : HTTP::Response
 Description : Login to vCloud Express and get the cookie with the authentication token

=cut

sub _login()
{
	my $self = shift;
    unless (ref($self) && $self->isa('VCL::Module::Provisioning::tmrk')) {
        die "subroutine can only be called as a module object method";
    }
	
    my $req = HTTP::Request->new(POST => vCLOUD.'/'.vCLOUD_API.'/login');
    $req->header('Content-Length' => 0);
    $req->authorization_basic($self->{username}, $self->{password});

    my $response = $ua->request($req);
    if (!$response->is_success) {
        $self->_barf($req, $response);
    }

	$cookie_jar->save;

	return $response;
}

#///////////////////////////////////////////////////////////////////////////// 
=head2 _request
        
 Parameters  : HTTP::Request
 Returns     : HTTP::Response
 Description : Invoke a HTTP request and return the response, performing 
               automatic retries if necessary.

=cut

sub _request
{
	my $self = shift;
	my $req = shift;
	my ($response);

    unless (ref($self) && $self->isa('VCL::Module::Provisioning::tmrk')) {
        die "subroutine can only be called as a module object method";
    }
	
	if ($verbose == 1) {
		print $req->as_string;
		print "\n";
	}
	
	for (my $count = 0; $count <= vCLOUD_RETRIES; $count++) {
	    $response = $ua->request($req);
	    if ($response->is_success) {
	    	if ($verbose == 1) {
	    		print $response->content;
	    		print "\n";
	    	}
    	    return $response;
	    }
	    if ($response->content =~ m/401 \- Unauthorized/) {
	    	sleep(3);
			$ua->cookie_jar->clear;
			$self->_login;
	    }
	}
	
   	$self->_barf($req, $response);
}

#///////////////////////////////////////////////////////////////////////////// 
=head2 versions
        
 Parameters  : none
 Returns     : none
 Description : Print available versions of the vCloud Express API.

=cut

sub versions
{
	my $self = shift;
    unless (ref($self) && $self->isa('VCL::Module::Provisioning::tmrk')) {
        die "subroutine can only be called as a module object method";
    }

    my $response = $ua->request(GET vCLOUD.'/versions');

    if ($response->is_success) {
		my $parser = XML::LibXML->new();
		my $doc = $parser->parse_string($response->content);

		my $xc = XML::LibXML::XPathContext->new( $doc->documentElement()  );
		$xc->registerNs('ns', 'http://www.vmware.com/vcloud/versions');

		my @n = $xc->findnodes('//ns:Version');
		foreach my $nod (@n) {
      		print $nod->textContent;
      		print "\n";
      	}
    }
    else {
        $self->_barf($response);
    }
}

sub _get
{
	my $self = shift;
    my $url = shift;
    my $req = HTTP::Request->new(GET => $url);
    my $response = $self->_request($req);
    
    print $response->content;
    print "\n";
}

#///////////////////////////////////////////////////////////////////////////// 
=head2 _xpath
        
 Parameters  : XML content, XPath string
 Returns     : String value
 Description : Find and return the value of a given Xpath in the XML content.

=cut

sub _xpath
{
	my $self = shift;
	my $content = shift;
	my $xpath = shift;
	my $ns = vCLOUD_NS;
	$ns = shift if @_;
	
    unless (ref($self) && $self->isa('VCL::Module::Provisioning::tmrk')) {
        die "subroutine can only be called as a module object method";
    }

	my $parser = XML::LibXML->new();
	my $doc = $parser->parse_string($content);

	my $xc = XML::LibXML::XPathContext->new( $doc->documentElement()  );
	$xc->registerNs('ns', $ns);
	return $xc->findvalue($xpath);
}

sub _xpath_wrap
{
	my $self = shift;
	my $content = shift;
	my $xpath = shift;
	my $ns = vCLOUD_NS;
	$ns = shift if @_;

    unless (ref($self) && $self->isa('VCL::Module::Provisioning::tmrk')) {
        die "subroutine can only be called as a module object method";
    }
    
	my $value = $self->_xpath($content, $xpath, $ns);
	if (!defined($value) || $value eq '') {
		print "$content\n\n";
	    die "Can't parse XPath: $xpath\n";
	}
	return $value;
}

#///////////////////////////////////////////////////////////////////////////// 
=head2 _create_vm
        
 Parameters  : none
 Returns     : none
 Description : Create a new Virtual Machine

=cut

sub _create_vm
{
	my $self = shift;
    unless (ref($self) && $self->isa('VCL::Module::Provisioning::tmrk')) {
        die "subroutine can only be called as a module object method";
    }
    my $vAppName = shift;
	my $vAppTemplate = shift;

	my $network = $self->_get_from_vdc('//ns:Network/@href');
	
	my $doc = XML::LibXML->createDocument;
	my $root = $doc->createElementNS( vCLOUD_NS, "InstantiateVAppTemplateParams" );
	$root->setNamespace("http://www.w3.org/2001/XMLSchema-instance", "xsi", 0);
	$doc->setDocumentElement( $root );
	$root->setAttribute("name", $vAppName);

	my $VAppTemplate = XML::LibXML::Element->new( "VAppTemplate" );
	$VAppTemplate->setAttribute("href", $vAppTemplate);
	$root->addChild($VAppTemplate);

	my $InstantiationParams;
	
	if (use_intantiation_params) {
		$InstantiationParams = XML::LibXML::Element->new( "InstantiationParams" );
		$root->addChild($InstantiationParams);
	
		my $ProductSection = XML::LibXML::Element->new( "ProductSection" );
		$ProductSection->setNamespace("http://www.vmware.com/vcloud/v0.8", "q1", 0);
		$ProductSection->setNamespace("http://schemas.dmtf.org/ovf/envelope/1", "ovf", 0);
		$InstantiationParams->addChild($ProductSection);
	
		my $Property = XML::LibXML::Element->new( "Property" );
		$Property->setNamespace("http://schemas.dmtf.org/ovf/envelope/1");
		$Property->setAttribute("ovf:key", "row");
		$Property->setAttribute("ovf:value", "Api");
		$ProductSection->addChild($Property);
	
		$Property = XML::LibXML::Element->new( "Property" );
		$Property->setNamespace("http://schemas.dmtf.org/ovf/envelope/1");
		$Property->setAttribute("ovf:key", "group");
		$Property->setAttribute("ovf:value", "Api");
		$ProductSection->addChild($Property);

		$Property = XML::LibXML::Element->new( "Property" );
		$Property->setNamespace("http://schemas.dmtf.org/ovf/envelope/1");
		$Property->setAttribute("ovf:key", "sshKeyFingerprint");
		$Property->setAttribute("ovf:value", "e4:b3:18:b3:0e:11:44:ef:2d:2b:44:ef:58:09:b5:8e");
		$ProductSection->addChild($Property);
	}
	
	my $vHardwareSection = XML::LibXML::Element->new( "VirtualHardwareSection" );
	if (defined($InstantiationParams)) {
		$InstantiationParams->addChild($vHardwareSection);
	}
	else {
		$root->addChild($vHardwareSection);
	}

	my $item = XML::LibXML::Element->new( "Item" );
	$item->setNamespace("http://schemas.dmtf.org/ovf/envelope/1");
	$vHardwareSection->addChild($item);

	my $instanceID = XML::LibXML::Element->new( "InstanceID" );
	$instanceID->setNamespace("http://schemas.dmtf.org/wbem/wscim/1/cimschema/2/CIM_ResourceAllocationSettingData");
	$instanceID->appendText("1");
	$item->addChild($instanceID);

	my $resourceType = XML::LibXML::Element->new( "ResourceType" );
	$resourceType->setNamespace("http://schemas.dmtf.org/wbem/wscim/1/cimschema/2/CIM_ResourceAllocationSettingData");
	$resourceType->appendText("3");
	$item->addChild($resourceType);

	my $virtualQuantity = XML::LibXML::Element->new( "VirtualQuantity" );
	$virtualQuantity->setNamespace("http://schemas.dmtf.org/wbem/wscim/1/cimschema/2/CIM_ResourceAllocationSettingData");
	$virtualQuantity->appendText("1");
	$item->addChild($virtualQuantity);

	$item = XML::LibXML::Element->new( "Item" );
	$item->setNamespace("http://schemas.dmtf.org/ovf/envelope/1");
	$vHardwareSection->addChild($item);

	$instanceID = XML::LibXML::Element->new( "InstanceID" );
	$instanceID->setNamespace("http://schemas.dmtf.org/wbem/wscim/1/cimschema/2/CIM_ResourceAllocationSettingData");
	$instanceID->appendText("2");
	$item->addChild($instanceID);

	$resourceType = XML::LibXML::Element->new( "ResourceType" );
	$resourceType->setNamespace("http://schemas.dmtf.org/wbem/wscim/1/cimschema/2/CIM_ResourceAllocationSettingData");
	$resourceType->appendText("4");
	$item->addChild($resourceType);

	$virtualQuantity = XML::LibXML::Element->new( "VirtualQuantity" );
	$virtualQuantity->setNamespace("http://schemas.dmtf.org/wbem/wscim/1/cimschema/2/CIM_ResourceAllocationSettingData");
	$virtualQuantity->appendText("512");
	$item->addChild($virtualQuantity);

	my $networkConfigSection = XML::LibXML::Element->new( "NetworkConfigSection" );
	if (defined($InstantiationParams)) {
		$InstantiationParams->addChild($networkConfigSection);
	}
	else {
		$root->addChild($vHardwareSection);
	}
	my $networkConfig = XML::LibXML::Element->new( "NetworkConfig" );
	$networkConfigSection->addChild($networkConfig);
	my $networkAssociation = XML::LibXML::Element->new( "NetworkAssociation" );
	$networkAssociation->setAttribute("href", $network);
	$networkConfig->addChild($networkAssociation);

    my $req = HTTP::Request->new(POST => $self->{vDC}.'/action/instantiatevAppTemplate');
    $req->header('Content-Length' => length($doc->toString));
    $req->header('Content-Type' => 'application/vnd.vmware.vcloud.instantiateVAppTemplateParams+xml');
    $req->content($doc->toString);

	print "Creating Virtual Machine $vAppName...";
	STDOUT->flush();
	my $response = $self->_request($req);
	print "done\n";

    #
	# This is what the response should look like 
	# 
	# <VApp href="https://services.vcloudexpress.terremark.com/api/v0.8/vapp/430879" type="application/vnd.vmware.vcloud.vApp+xml" name="MyApplication" status="1" size="10" xmlns="http://www.vmware.com/vcloud/v0.8" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema">
	#   <Link rel="up" href="https://services.vcloudexpress.terremark.com/api/v0.8/vdc/3068" type="application/vnd.vmware.vcloud.vdc+xml"/>
	# </VApp>

	print "VM is being created, this may take several minutes...";
	STDOUT->flush();
    sleep(30);

	$self->{vApp} = $self->_xpath_wrap($response->content, '//ns:VApp/@href');

	my $status;
	for (my $count = 0; $count <= TIMEOUT_DEPLOY_MINS * (60 / POLLING_INTERVAL_SECS); $count++) {
		$req = HTTP::Request->new(GET => $self->{vApp});
    	$response = $self->_request($req);
		$status = $self->_xpath_wrap($response->content, '//ns:VApp/@status');
		if ($status eq '0' || $status eq '1') {
		    sleep(POLLING_INTERVAL_SECS);
		}
		else {
			last;
		}
	}
	die "VM failed to deploy" if ($status ne '2' && $status ne '3');
	
	print "done\n";
}

sub _connect_to_internet
{
	my $self = shift;
	my $port = shift;
    unless (ref($self) && $self->isa('VCL::Module::Provisioning::tmrk')) {
        die "subroutine can only be called as a module object method";
    }

	my $internetServices = $self->_get_from_vdc('//ns:Link[@name=\'Internet Services\']/@href');

	# build the xml document to open up a TCP port on a new public IP address
	my $doc = XML::LibXML->createDocument;
	my $root = $doc->createElementNS( "urn:tmrk:vCloudExpressExtensions-1.6", "CreateInternetServiceRequest" );
	$doc->setDocumentElement( $root );
	my $element = XML::LibXML::Element->new( "Name" );
	$element->appendText("TCP Internet Service");
	$root->addChild($element);
	$element = XML::LibXML::Element->new( "Protocol" );
	$element->appendText("TCP");
	$root->addChild($element);
	$element = XML::LibXML::Element->new( "Port" );
	$element->appendText($port);
	$root->addChild($element);
	$element = XML::LibXML::Element->new( "Enabled" );
	$element->appendText("true");
	$root->addChild($element);

    my $req = HTTP::Request->new(POST => $internetServices);
    $req->header('Content-Length' => length($doc->toString));
    $req->header('Content-Type' => 'application/vnd.vmware.vcloud.createInternetService+xml');
    $req->content($doc->toString);
 
	print "Creating Internet Service...";
	STDOUT->flush();
    my $response = $self->_request($req);
	print "done\n";

	# get a link to the internet service we just created and save the public IP address
	my $InternetService = $self->_xpath_wrap($response->content, '//ns:InternetService/ns:Href', 'urn:tmrk:vCloudExpressExtensions-1.6');
	$self->{PublicIpAddress} = $self->_xpath_wrap($response->content, '//ns:PublicIpAddress/ns:Name', 'urn:tmrk:vCloudExpressExtensions-1.6');

	# build the xml request to create a node service which will tie the internet service to the VM
	$doc = XML::LibXML->createDocument;
	$root = $doc->createElementNS( "urn:tmrk:vCloudExpressExtensions-1.6", "CreateNodeServiceRequest" );
	$doc->setDocumentElement( $root );
	$element = XML::LibXML::Element->new( "IpAddress" );
	$element->appendText($self->{IpAddress});
	$root->addChild($element);
	$element = XML::LibXML::Element->new( "Name" );
	$element->appendText("My Node Service");
	$root->addChild($element);
	$element = XML::LibXML::Element->new( "Port" );
	$element->appendText($port);
	$root->addChild($element);
	$element = XML::LibXML::Element->new( "Enabled" );
	$element->appendText("true");
	$root->addChild($element);

    $req = HTTP::Request->new(POST => $InternetService."/nodeServices");
    $req->header('Content-Length' => length($doc->toString));
    $req->header('Content-Type' => 'application/vnd.vmware.vcloud.createInternetService+xml');
    $req->content($doc->toString);
 
	print "Creating Node Service...";
	STDOUT->flush();
    $response = $self->_request($req);
	print "done\n";
}

sub _is_connected_internet
{
	my $self = shift;
    unless (ref($self) && $self->isa('VCL::Module::Provisioning::tmrk')) {
        die "subroutine can only be called as a module object method";
    }

    if (!$self->{IpAddress}) {
        die "Private IP address of VM is not known";
    }

	my $internetServices = $self->_get_from_vdc('//ns:Link[@name=\'Internet Services\']/@href');

	print "Getting all internet services...";
	STDOUT->flush();
    my $req = HTTP::Request->new(GET => $internetServices);
    my $response = $self->_request($req);
	print "done\n";

	my $parser = XML::LibXML->new();
	my $doc = $parser->parse_string($response->content);

	my $xc = XML::LibXML::XPathContext->new( $doc->documentElement()  );
	$xc->registerNs('ns', 'urn:tmrk:vCloudExpressExtensions-1.6');

	my @nodes = $xc->findnodes('//ns:InternetService/ns:Href');
	foreach my $internetService (@nodes) {
		my $xc_is = XML::LibXML::XPathContext->new( $internetService );
		$xc_is->registerNs('ns', 'urn:tmrk:vCloudExpressExtensions-1.6');
		my $id = $xc_is->findvalue('//ns:InternetService/ns:Id');
		my $url = $xc_is->findvalue('//ns:InternetService/ns:Href');
		my $PublicIpAddress = $xc_is->findvalue('//ns:PublicIpAddress/ns:Name');

		print "Getting node services on internet service $id...";
		STDOUT->flush();

	    my $req = HTTP::Request->new(GET => $url."/nodeServices");
	    my $response = $self->_request($req);
		print "done\n";

		my $IpAddress = $self->_xpath($response->content, '//ns:IpAddress', 'urn:tmrk:vCloudExpressExtensions-1.6');

  		if ($IpAddress eq $self->{IpAddress}) {
  			$self->{PublicIpAddress} = $PublicIpAddress;
  			return 1;
  		}
   	}

	return 0;
}

#///////////////////////////////////////////////////////////////////////////// 
=head2 power_on
        
 Parameters  : none
 Returns     : none
 Description : Power-on a Virtual Machine

=cut

sub power_on
{
	my $self = shift;
    unless (ref($self) && $self->isa('VCL::Module::Provisioning::tmrk')) {
        die "subroutine can only be called as a module object method";
    }
	my $vApp = shift;
	
	print "Powering up VM, this may take several minutes...";
	STDOUT->flush();
	my $req = HTTP::Request->new(POST => $vApp.'/power/action/powerOn');
    $req->header('Content-Length' => 0);
   	my $response = $self->_request($req);
    sleep(30);
    my $status;
	for (my $count = 0; $count <= TIMEOUT_POWER_ON_MINS * (60 / POLLING_INTERVAL_SECS); $count++) {
		$req = HTTP::Request->new(GET => $vApp);
    	$response = $self->_request($req);
		$status = $self->_xpath_wrap($response->content, '//ns:VApp/@status');
		if ($status ne '4') {
		    sleep(POLLING_INTERVAL_SECS);
		}
		else {
			last;
		}
	}
	die "VM failed to power on" if ($status ne '4');
	print "done\n";
}

#///////////////////////////////////////////////////////////////////////////// 
=head2 power_off
        
 Parameters  : none
 Returns     : none
 Description : Power-off a Virtual Machine

=cut

sub power_off
{
	my $self = shift;
    unless (ref($self) && $self->isa('VCL::Module::Provisioning::tmrk')) {
        die "subroutine can only be called as a module object method";
    }

	my $vApp = shift;
	
	print "Powering off VM, this may take several minutes...";
	STDOUT->flush();
	my $req = HTTP::Request->new(POST => $vApp.'/power/action/powerOff');
    $req->header('Content-Length' => 0);
   	my $response = $self->_request($req);
    sleep(30);
    my $status;
	for (my $count = 0; $count <= TIMEOUT_POWER_OFF_MINS * (60 / POLLING_INTERVAL_SECS); $count++) {
		$req = HTTP::Request->new(GET => $self->{vApp});
    	$response = $self->_request($req);
		$status = $self->_xpath_wrap($response->content, '//ns:VApp/@status');
		if ($status ne '2') {
		    sleep(POLLING_INTERVAL_SECS);
		}
		else {
			last;
		}
	}
	die "VM failed to power off" if ($status ne '2');
	print "done\n";
}

#/////////////////////////////////////////////////////////////////////////////

=head2 does_image_exist

 Parameters  : imagename
 Returns     : 0 or 1
 Description : Searches the catalog for requested image
               returns 1 if found or 0 if not

=cut

sub does_image_exist
{
	my $self = shift;
    unless (ref($self) && $self->isa('VCL::Module::Provisioning::tmrk')) {
        die "subroutine can only be called as a module object method";
    }

    # get the image name, first try passed argument, then data
    my $image_name = shift;
    $image_name = vCLOUD_IMAGE if !$image_name;
    if (!$image_name) {
        die "unable to determine image name";
    }

	# get catalog of images that are available	
    my $req = HTTP::Request->new(GET => $self->{catalog});
    my $response = $self->_request($req);

	# look for the image name in the catalog
	my $catalogItem = $self->_xpath($response->content, '//ns:CatalogItem[@name=\''.$image_name.'\']/@href');
	if (!$catalogItem) {
        die "Image $image_name not found in catalog";
	}

	# get detailed information on the catalog item
    $req = HTTP::Request->new(GET => $catalogItem);
    $response = $self->_request($req);

	return 1;
}

#/////////////////////////////////////////////////////////////////////////////

=head2 _get_vapp_template

 Parameters  : imagename
 Returns     : URL to the vAppTemplate
 Description : Searches the catalog for requested image

=cut

sub _get_vapp_template
{
	my $self = shift;
    unless (ref($self) && $self->isa('VCL::Module::Provisioning::tmrk')) {
        die "subroutine can only be called as a module object method";
    }

    # Get the image name, first try passed argument, then data
    my $image_name = shift;
    $image_name = vCLOUD_IMAGE if !$image_name;
    if (!$image_name) {
        die "unable to determine image name";
    }

	my $catalog = $self->_get_from_vdc('//ns:Link[@type=\'application/vnd.vmware.vcloud.catalog+xml\']/@href');
	
	print "Getting catalog of images...";
	STDOUT->flush();
    my $req = HTTP::Request->new(GET => $catalog);
    my $response = $self->_request($req);
	print "done\n";

	my $catalogItem = $self->_xpath($response->content, '//ns:CatalogItem[@name=\''.$image_name.'\']/@href');
	if (!$catalogItem) {
        die "Image $image_name not found in catalog";
	}

	print "Getting catalog item ".$image_name."...";
	STDOUT->flush();
    $req = HTTP::Request->new(GET => $catalogItem);
    $response = $self->_request($req);
	print "done\n";

	return $self->_xpath_wrap($response->content, '//ns:Entity[@type=\'application/vnd.vmware.vcloud.vAppTemplate+xml\']/@href');
}

#///////////////////////////////////////////////////////////////////////////// 
=head2 load
        
 Parameters  : vAppName
 Returns     : 1 if successful, 0 if error
 Description : Load a new Virtual Machine 

=cut

sub load
{
    my($self, %args) = @_;
#	my $self = shift;
	my $vAppName = $args{vAppName};

    unless (ref($self) && $self->isa('VCL::Module::Provisioning::tmrk')) {
        die "subroutine can only be called as a module object method";
    }

	# Look to see if the vApp already exists
	my $vApp = $self->_get_from_vdc('//ns:ResourceEntity[@type=\'application/vnd.vmware.vcloud.vApp+xml\' and @name=\''.$vAppName.'\']/@href');
	if (!$vApp) {
		# get the image template
		my $vAppTemplate = $self->_get_vapp_template;

		# create the VM
		$self->_create_vm($vAppName, $vAppTemplate);
		
		# should be able to find the vApp now
		$vApp = $self->_get_from_vdc('//ns:ResourceEntity[@type=\'application/vnd.vmware.vcloud.vApp+xml\' and @name=\''.$vAppName.'\']/@href');
	}
	
	# get the status and private IP address of the VM
	my $req = HTTP::Request->new(GET => $vApp);
   	my $response = $self->_request($req);
	my $status = $self->_xpath_wrap($response->content, '//ns:VApp/@status');
	$self->{IpAddress} = $self->_xpath_wrap($response->content, '//ns:NetworkConnection/ns:IpAddress');
	
	if ($status eq "2") {
		$self->power_on($vApp);
	}

	if (!$self->_is_connected_internet) {
		$self->_connect_to_internet(22);
	}
	
	# Enable SSH login to VM through the public interface
	print "Enabling SSH login to VM through public interface...";
	STDOUT->flush();
	my $ssh = Net::SSH::Perl->new($self->{IpAddress}, identity_files => $self->{identity_files});
	$ssh->login("vcloud");
	$self->_ssh_cmd($ssh, "sudo sed -i s/'PasswordAuthentication no'/'PasswordAuthentication yes'/ /etc/ssh/sshd_config");
	$self->_ssh_cmd($ssh, "sudo /etc/init.d/sshd restart");
	$self->_ssh_cmd($ssh, "echo ".$self->{password}." | sudo passwd --stdin vcloud");
	print "done\n";
	
	print "Public IP Address: ".$self->{PublicIpAddress}."\n";
		
	return 1;
}

sub _get_from_vdc
{
	my $self = shift;
    unless (ref($self) && $self->isa('VCL::Module::Provisioning::tmrk')) {
        die "subroutine can only be called as a module object method";
    }

	my $xpath = shift;
	
    my $req = HTTP::Request->new(GET => $self->{vDC});
    my $response = $self->_request($req);
    return $self->_xpath($response->content, $xpath);
}

sub _get_template_desc
{
	my $self = shift;
    unless (ref($self) && $self->isa('VCL::Module::Provisioning::tmrk')) {
        die "subroutine can only be called as a module object method";
    }
	my $vAppTemplate = shift;
	
	print "Getting template description...";
	STDOUT->flush();
    my $req = HTTP::Request->new(GET => $vAppTemplate);
    my $response = $self->_request($req);
	print "done\n";

	my $description = $self->_xpath_wrap($response->content, '//ns:Description');
	print "\n$description\n";
}

sub _ssh_cmd
{
	my $self = shift;
	my $ssh = shift;
	my $cmd = shift;

    unless (ref($self) && $self->isa('VCL::Module::Provisioning::tmrk')) {
        die "subroutine can only be called as a module object method";
    }
	
	my($stdout, $stderr, $exit) = $ssh->cmd($cmd);
	if ($exit != 0) {
		die $stderr;
	}
}

1;
