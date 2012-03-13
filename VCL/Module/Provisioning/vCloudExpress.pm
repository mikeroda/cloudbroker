#!/usr/bin/perl -w
###############################################################################
# Mike Roda    mike@mikeroda.com
#
###############################################################################

=head1 NAME

VCL::Module::Provisioning::vCloudExpress

=head1 SYNOPSIS

 VCL module to support Terremark vCloud Express v0.8 API Provisioning

=head1 DESCRIPTION

 This module provides support for Terremark vCloud Express API 0.8a-ext1.6
 http://vcloudexpress.terremark.com/
 API documentation:
 https://community.vcloudexpress.terremark.com/en-us/product_docs/m/vcefiles/1639/download.aspx

=cut

##############################################################################
package VCL::Module::Provisioning::vCloudExpress;

our $VERSION = '0.1';

use strict;
use warnings;
use diagnostics;
use English qw( -no_match_vars );

use constant vCLOUD => 'https://services.vcloudexpress.terremark.com/api';
use constant vCLOUD_API => 'v0.8a-ext1.6';
use constant vCLOUD_RETRIES => 2;
use constant vCLOUD_IMAGE => 'CentOS 5 (32-bit)';
use constant vCLOUD_NS => 'http://www.vmware.com/vcloud/v0.8';
use constant use_intantiation_params => 0;

use HTTP::Request;
use HTTP::Request::Common;
use HTTP::Cookies;
use LWP::UserAgent;
use Term::ReadKey;
use IO::Socket::SSL;
use XML::LibXML;

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
    unless (ref($self) && $self->isa('VCL::Module::Provisioning::vCloudExpress')) {
        die "subroutine can only be called as a module object method";
    }
        
	$cookie_jar = HTTP::Cookies->new(
    file => "$ENV{'HOME'}/lwp_cookies.dat",
	    autosave => 1,
    	ignore_discard => 0,
	);

	$ua = LWP::UserAgent->new;
	$ua->cookie_jar($cookie_jar);

    $self->_login() || return 0;
        
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
    
    unless (ref($self) && $self->isa('VCL::Module::Provisioning::vCloudExpress')) {
        die "subroutine can only be called as a module object method";
    }
    
    my $message = $response->content;

	print "\n";
	print $req->as_string;
	print "\n\n";
    die "ERROR: $message\n";
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
    unless (ref($self) && $self->isa('VCL::Module::Provisioning::vCloudExpress')) {
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

    unless (ref($self) && $self->isa('VCL::Module::Provisioning::vCloudExpress')) {
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
    unless (ref($self) && $self->isa('VCL::Module::Provisioning::vCloudExpress')) {
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
	
    unless (ref($self) && $self->isa('VCL::Module::Provisioning::vCloudExpress')) {
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

    unless (ref($self) && $self->isa('VCL::Module::Provisioning::vCloudExpress')) {
        die "subroutine can only be called as a module object method";
    }
    
	my $value = _xpath($content, $xpath, $ns);
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
    unless (ref($self) && $self->isa('VCL::Module::Provisioning::vCloudExpress')) {
        die "subroutine can only be called as a module object method";
    }
	
	#
	# Creating Virtual Machine instance.  This is what the XML should look like 
	#
	#   <InstantiateVAppTemplateParams xmlns="http://www.vmware.com/vcloud/v0.8" name="VM1">
	#    <VAppTemplate href="https://services.vcloudexpress.terremark.com/api/v0.8a-ext1.6/vappTemplate/5"/>
	#    <InstantiationParams>
	#      <ProductSection xmlns:q1="http://www.vmware.com/vcloud/v0.8" xmlns:ovf="http://schemas.dmtf.org/ovf/envelope/1">
	#        <Property xmlns="http://schemas.dmtf.org/ovf/envelope/1" ovf:key="sshKeyFingerprint" ovf:value="e4:b3:18:b3:0e:11:44:ef:2d:2b:44:ef:58:09:b5:8e"/>
	#	     <Property xmlns="http://schemas.dmtf.org/ovf/envelope/1" ovf:key="row" ovf:value="Api"/>
	#        <Property xmlns="http://schemas.dmtf.org/ovf/envelope/1" ovf:key="group" ovf:value="Api"/>
	#      </ProductSection>
	#      <VirtualHardwareSection>
	#        <Item xmlns="http://schemas.dmtf.org/ovf/envelope/1">
	#         <InstanceID xmlns="http://schemas.dmtf.org/wbem/wscim/1/cimschema/2/CIM_ResourceAllocationSettingData">1</InstanceID>
	#		  <ResourceType xmlns="http://schemas.dmtf.org/wbem/wscim/1/cimschema/2/CIM_ResourceAllocationSettingData">3</ResourceType>
	#		  <VirtualQuantity xmlns="http://schemas.dmtf.org/wbem/wscim/1/cimschema/2/CIM_ResourceAllocationSettingData">1</VirtualQuantity>
	#		 </Item>
	#		 <Item xmlns="http://schemas.dmtf.org/ovf/envelope/1">
	#		  <InstanceID xmlns="http://schemas.dmtf.org/wbem/wscim/1/cimschema/2/CIM_ResourceAllocationSettingData">2</InstanceID>
	#		  <ResourceType xmlns="http://schemas.dmtf.org/wbem/wscim/1/cimschema/2/CIM_ResourceAllocationSettingData">4</ResourceType>
	# 		  <VirtualQuantity xmlns="http://schemas.dmtf.org/wbem/wscim/1/cimschema/2/CIM_ResourceAllocationSettingData">512</VirtualQuantity>
	#		 </Item>
	#      </VirtualHardwareSection>
	#	   <NetworkConfigSection>
	#		<NetworkConfig>
	#		  <NetworkAssociation href="https://services.vcloudexpress.terremark.com/api/v0.8a-ext1.6/network/2110"/>
	#		</NetworkConfig>
	#      </NetworkConfigSection>
	#    </InstantiationParams>
	#   </InstantiateVAppTemplateParams>

	my $doc = XML::LibXML->createDocument;
	my $root = $doc->createElementNS( vCLOUD_NS, "InstantiateVAppTemplateParams" );
	$root->setNamespace("http://www.w3.org/2001/XMLSchema-instance", "xsi", 0);
	$doc->setDocumentElement( $root );
	$root->setAttribute("name", $self->{vAppName});

	my $vAppTemplate = XML::LibXML::Element->new( "VAppTemplate" );
	$vAppTemplate->setAttribute("href", $self->{vAppTemplate});
	$root->addChild($vAppTemplate);

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
	$networkAssociation->setAttribute("href", $self->{network});
	$networkConfig->addChild($networkAssociation);

    my $req = HTTP::Request->new(POST => $self->{vDC}.'/action/instantiatevAppTemplate');
    $req->header('Content-Length' => length($doc->toString));
    $req->header('Content-Type' => 'application/vnd.vmware.vcloud.instantiateVAppTemplateParams+xml');
    $req->content($doc->toString);

	print "\nCreating Virtual Machine ".$self->{vAppName}."...";
	STDOUT->flush();
	my $response = $self->_request($req);
	print "done\n";

    #
	# This is what the response should look like 
	# 
	# <VApp href="https://services.vcloudexpress.terremark.com/api/v0.8/vapp/430879" type="application/vnd.vmware.vcloud.vApp+xml" name="MyApplication" status="1" size="10" xmlns="http://www.vmware.com/vcloud/v0.8" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema">
	#   <Link rel="up" href="https://services.vcloudexpress.terremark.com/api/v0.8/vdc/3068" type="application/vnd.vmware.vcloud.vdc+xml"/>
	# </VApp>

	print "\nVM is being created, this may take several minutes...";
	STDOUT->flush();
    sleep(30);

	$self->{vApp} = $self->_xpath_wrap($response->content, '//ns:VApp/@href');

	for (my $count = 0; $count <= 30; $count++) {
		$req = HTTP::Request->new(GET => $self->{vApp});
    	$response = $self->_request($req);
		my $status = $self->_xpath_wrap($response->content, '//ns:VApp/@status');
		if ($status eq '0' || $status eq '1') {
		    sleep(30);
		}
		else {
			last;
		}
	}
	print "done\n";
}

sub _create_internet_service
{
	my $self = shift;
    unless (ref($self) && $self->isa('VCL::Module::Provisioning::vCloudExpress')) {
        die "subroutine can only be called as a module object method";
    }

	my $element;

	# Create an Internet service
	#	<InternetService xmlns:xsi="http://www.w3.org/2001/XMLSchemainstance" xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns="urn:tmrk:vCloudExpress-1.0:request:createInternetService">
	#	<Name>IS_for_Jim</Name>
	#	<Protocol>HTTP</Protocol>
	#	<Port>80</Port>
	#	<Enabled>false</Enabled>
	#	<Description>Some test service</Description>
	#	</InternetService>

	my $doc = XML::LibXML->createDocument;
	my $root = $doc->createElementNS( "urn:tmrk:vCloudExpress-1.0:request:createInternetService", "InternetService" );
	$doc->setDocumentElement( $root );
	$element = XML::LibXML::Element->new( "Name" );
	$element->appendText("TCP Internet Service");
	$root->addChild($element);
	$element = XML::LibXML::Element->new( "Protocol" );
	$element->appendText("TCP");
	$root->addChild($element);
	$element = XML::LibXML::Element->new( "Port" );
	$element->appendText("22");
	$root->addChild($element);
	$element = XML::LibXML::Element->new( "Enabled" );
	$element->appendText("true");
	$root->addChild($element);

    my $req = HTTP::Request->new(POST => $self->{internetServices});
    $req->header('Content-Length' => length($doc->toString));
    $req->header('Content-Type' => 'application/vnd.vmware.vcloud.createInternetService+xml');
    $req->content($doc->toString);
 
	print "\nCreating Internet Service...";
	STDOUT->flush();
    my $response = $self->_request($req);
	print "done\n";

	my $InternetServiceID = $self->_xpath_wrap($response->content, '//ns:InternetService/ns:Id', 'urn:tmrk:vCloudExpress-1.0');

	#	<NodeService xmlns:xsi="http://www.w3.org/2001/XMLSchemainstance" xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns="urn:tmrk:vCloudExpress-1.0:request:createNodeService">
	#	<IpAddress>172.16.20.3</IpAddress>
	#	<Name>Node for Jim</Name>
	#	<Port>80</Port>
	#	<Enabled>false</Enabled>
	#	<Description>Some test node</Description>
	#	</NodeService>

	$doc = XML::LibXML->createDocument;
	$root = $doc->createElementNS( "urn:tmrk:vCloudExpress-1.0:request:createNodeService", "NodeService" );
	$doc->setDocumentElement( $root );
	$element = XML::LibXML::Element->new( "IpAddress" );
	$element->appendText($self->{IpAddress});
	$root->addChild($element);
	$element = XML::LibXML::Element->new( "Name" );
	$element->appendText("My Node Service");
	$root->addChild($element);
	$element = XML::LibXML::Element->new( "Port" );
	$element->appendText("22");
	$root->addChild($element);
	$element = XML::LibXML::Element->new( "Enabled" );
	$element->appendText("true");
	$root->addChild($element);

    $req = HTTP::Request->new(POST => vCLOUD.'/'.vCLOUD_API."/internetServices/".$InternetServiceID."/nodes");
    $req->header('Content-Length' => length($doc->toString));
    $req->header('Content-Type' => 'application/vnd.vmware.vcloud.createInternetService+xml');
    $req->content($doc->toString);
 
	print "\nCreating Node Service...";
	STDOUT->flush();
    $response = $self->_request($req);
	print "done\n";
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
    unless (ref($self) && $self->isa('VCL::Module::Provisioning::vCloudExpress')) {
        die "subroutine can only be called as a module object method";
    }

	print "\nPowering up VM, this may take several minutes...";
	STDOUT->flush();
	my $req = HTTP::Request->new(POST => $self->{vApp}.'/power/action/powerOn');
    $req->header('Content-Length' => 0);
   	my $response = $self->_request($req);
    sleep(30);
	for (my $count = 0; $count <= 10; $count++) {
		$req = HTTP::Request->new(GET => $self->{vApp});
    	$response = $self->_request($req);
		my $status = $self->_xpath_wrap($response->content, '//ns:VApp/@status');
		if ($status ne '4') {
		    sleep(30);
		}
		else {
			last;
		}
	}
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
    unless (ref($self) && $self->isa('VCL::Module::Provisioning::vCloudExpress')) {
        die "subroutine can only be called as a module object method";
    }

	print "\nPowering off VM, this may take several minutes...";
	STDOUT->flush();
	my $req = HTTP::Request->new(POST => $self->{vApp}.'/power/action/powerOff');
    $req->header('Content-Length' => 0);
   	my $response = $self->_request($req);
    sleep(30);
	for (my $count = 0; $count <= 10; $count++) {
		$req = HTTP::Request->new(GET => $self->{vApp});
    	$response = $self->_request($req);
		my $status = $self->_xpath_wrap($response->content, '//ns:VApp/@status');
		if ($status ne '2') {
		    sleep(30);
		}
		else {
			last;
		}
	}
	print "done\n";
}

#/////////////////////////////////////////////////////////////////////////////

=head2 does_image_exist

 Parameters  : imagename
 Returns     : 0 or 1
 Description : Searches the catalog for requested image
               returns 1 if found or 0 if not
               saves URL for the image as $self->{vAppTemplate}

=cut

sub does_image_exist
{
	my $self = shift;
    unless (ref($self) && $self->isa('VCL::Module::Provisioning::vCloudExpress')) {
        die "subroutine can only be called as a module object method";
    }

    # Get the image name, first try passed argument, then data
    my $image_name = shift;
    $image_name = vCLOUD_IMAGE if !$image_name;
    if (!$image_name) {
        die "unable to determine image name";
    }
	
	print "\nGetting catalog of images...";
	STDOUT->flush();
    my $req = HTTP::Request->new(GET => $self->{catalog});
    my $response = $self->_request($req);
	print "done\n";

	my $catalogItem = $self->_xpath($response->content, '//ns:CatalogItem[@name=\''.$image_name.'\']/@href');
	if (!defined($catalogItem) || $catalogItem eq '') {
        die "Image $image_name not found in catalog";
	}

	print "\nGetting catalog item ".$image_name."...";
	STDOUT->flush();
    $req = HTTP::Request->new(GET => $catalogItem);
    $response = $self->_request($req);
	print "done\n";

	$self->{vAppTemplate} = $self->_xpath_wrap($response->content, '//ns:Entity[@type=\'application/vnd.vmware.vcloud.vAppTemplate+xml\']/@href');
	
	return 1;
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
	$self->{vAppName} = $args{vAppName};

    unless (ref($self) && $self->isa('VCL::Module::Provisioning::vCloudExpress')) {
        die "subroutine can only be called as a module object method";
    }

	my ($req);
	my ($response);

	print "\nLogging into vCloud Express...";
	STDOUT->flush();
	$response = $self->_login;
	print "done\n";
	
	my $org = $self->_xpath_wrap($response->content, '//ns:Org/@href');

	print "\nGetting organization...";
	STDOUT->flush();
    $req = HTTP::Request->new(GET => $org);
    $response = $self->_request($req);
	print "done\n";

	$self->{vDC} = $self->_xpath_wrap($response->content, '//ns:Link[@type=\'application/vnd.vmware.vcloud.vdc+xml\']/@href');

	print "\nGetting vDC...";
	STDOUT->flush();
    $req = HTTP::Request->new(GET => $self->{vDC});
    $response = $self->_request($req);
	print "done\n";

	$self->{network} = $self->_xpath_wrap($response->content, '//ns:Network/@href');
	$self->{catalog} = $self->_xpath_wrap($response->content, '//ns:Link[@type=\'application/vnd.vmware.vcloud.catalog+xml\']/@href');
	$self->{internetServices} = $self->_xpath_wrap($response->content, '//ns:Link[@name=\'Internet Services\']/@href');

	# Look to see if the vApp already exists
	$self->{vApp} = $self->_xpath($response->content, '//ns:ResourceEntity[@type=\'application/vnd.vmware.vcloud.vApp+xml\' and @name=\''.$self->{vAppName}.'\']/@href');
	
	$self->does_image_exist;

	print "\nGetting IP address and current state of VM...";
	STDOUT->flush();
	$req = HTTP::Request->new(GET => $self->{vApp});
   	$response = $self->_request($req);
	my $status = $self->_xpath_wrap($response->content, '//ns:VApp/@status');
	$self->{IpAddress} = $self->_xpath_wrap($response->content, '//ns:NetworkConnection/ns:IpAddress');
	print "done\n";
	
	if ($status eq "2") {
		$self->_power_on;
	}
	
	print "\nGetting template description...";
	STDOUT->flush();
    $req = HTTP::Request->new(GET => $self->{vAppTemplate});
    $response = $self->_request($req);
	print "done\n";

	my $description = $self->_xpath_wrap($response->content, '//ns:Description');
	print "\n$description\n";
	return 1;
}

1;
