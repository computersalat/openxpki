#!/usr/bin/perl

use CGI;
use CGI::Session;
use JSON;
use Data::Dumper;
use Log::Log4perl qw(:easy);

Log::Log4perl->easy_init($DEBUG);
   

sub handle {


    my $q = shift;    
    my $session = new CGI::Session(undef, $q, {Directory=>'/tmp'});
    my $session_id = $session->id;            
    # the action param indicates what is requested, no action = Home/Login 
    
#    my $query = $q->param('record[subject]');
    
#$session->param("my_name", $name);
    
    logger()->debug('Session id ' . $session_id);
    
    my $res;
 
    my $action = $q->param('action') || '';
    my $user = $session->param('user');
    # Login page
    
    logger()->debug('User ' .  Dumper $user );
        
    if (!$user ||  !$user->{login}) {
=cut        
        return {  
            'page' => {
                'label' => 'OpenXPKI Login',
                'desc' => 'Please select authentication handler'
            },
            'section' => [{ 'action' => 'login', 'fields' => [
                { name => 'authstack', 'label' => 'Auth System', 'type' => 'select', 'options' => [
                    { 'label' => 'Local', 'value' => 'local' },
                    { 'label' => 'Remote', 'value' => 'remote' }
                ]},                
            ]}]
        };
=cut        
        
        if ($action eq 'login') {
            $res = handle_login( $q );            
            $session->param("user", { 'login' => 'admin' }) unless( $res->{error});           
        } else {
            $res = { 'page' => 'login' };
        }
         
        logger()->debug('Result after handling' . Dumper $res);
       
    } elsif ($action eq 'logout') {
        $session->delete();
        $session_id = '';
        $res = {'page' => 'login' , 'status' => { 'level' => 'success', 'message' => 'Session terminated' } };         
    } elsif ($action eq 'certsearch') {
        $res = handle_certsearch( $q );
    } elsif ($q->param('page')) {
        $res = {'page' => $q->param('page') };
    }
    
    print $q->header( -cookie=> $q->cookie(CGISESSID =>  $session_id), -type => 'application/json' );
    
    # error occured, just send error hash
    return $res unless($res->{page});
    my $page = $res->{page};
        
    if ($page eq 'login') {
        return {  
            'page' => {
                'label' => 'OpenXPKI Login',
                'desc' => 'Please log in ;)',
            },
            'main' => [{ 'action' => 'login','type' => 'form', 'fields' => [
                { 'name' => 'username', 'label' => 'Username', 'type' => 'text' },
                { 'name' => 'password', 'label' => 'Password', 'type' => 'password' },
            ]}]
        };
    } elsif ($page eq 'home') { 
        return {  
            'page' => {
                'label' => 'Welcome to OpenXPKI',             
            }, 
            'main' => [{'type' => 'text'}],           
            'status' => $res->{status}
        };
    } elsif ($page eq 'certsearch') {
        return {  
            'page' => {
                'label' => 'Certificate Search',
                'desc' => 'You can search for certs here.',
                
            },
            'main' => [{ 'type' => 'form','action' => 'certsearch', 'fields' => [
                { 'name' => 'subject', 'label' => 'Subject', 'type' => 'text' },
                { 'name' => 'issuer', 'label' => 'Issuer', 'type' => 'text' },
            ]}]
        };
    } elsif($page eq 'grid') {
        
        return {  
            'page' => {
                'label' => 'Your Searchresult',
                                
            },
            'main' => [{
                'type' => 'grid', result => $res->{result},        
            }]};               
    }
        
        
}
        
sub handle_login {
    
    my $q = shift;
    
    if ($q->param('username') eq 'admin' && $q->param('password') eq 'openxpki') {
        return { 'page' => 'home', 'status' => { 'level' => 'success', 'message' => 'Login successful' } };
    }

    return { 'error' => {
        'username' => 'invalid',
        'password' => 'invalid',
    },
    'status' => { 'level' => 'error', 'message' => 'Login credentials are wrong!' } 
    };

}

sub handle_certsearch {
    
    my $q = shift;
    
    my $subject = $q->param('subject');
    my $issuer  = $q->param('issuer');
    
    return {'status' => { 'level' => 'error', 'message' => 'Invalid search params!' }} unless ($subject || $issuer);
    
    return { 'page' => 'grid',
        'result' => {
            'count' => 2,
            'page'  => 1,
            'pagecount' => 25,
            records => [{
                'recid' =>  1,
                'serial' => '0123',
                'subject' => 'CN=John M Miller,DC=My Company,DC=com',
                'email' => 'john.miller@my-company.com',
                'notbefore' => 1379587708,
                'notafter' => 1395226097,
                'issuer' => 'CN=CA 1,O=OpenXOKI Testing,ST=Bayern,C=DE',
                'identifier' => 'swBdX644xhsn-brmKLbKOb8buMc',
            },{
                'recid' =>  2,
                'serial' => '0456',
                'subject' => 'CN=Bob Builder,DC=My Company,DC=com',
                'email' => '',
                'notbefore' => 1379587517,
                'notafter' => 1411113697,
                'issuer' => 'CN=CA 1,O=OpenXOKI Testing,ST=Bayern,C=DE',
                'identifier' => 'qqA2HidUoRvlSLhsFIB6_ps6CpQ',
            }]               
        }
    };    
    
}


sub logger {
    
    return Log::Log4perl->get_logger();
}

my $q = CGI->new;   
my $log = 

my $json = new JSON();    

my $ret = handle($q);
    
if (ref $ret eq 'HASH') {   
    print $json->encode($ret);
} else {
    print $json->encode({ 'level' => 'error', 'message' => 'Application error!' });
} 


1;

=head1 DISCLAIMER

This is a stupid mock up for our ui development, it does do anything usefule
and does not care about any input security, so please just dont use it.


=head1 General

=head2 Request format

Each request should have either the param action or page set, the return is
always a json hash either holding a definition for a new page or an error.

The global structure is as follows:

  {
      page => {
          type => <page type> (form, grid, text),
          label => string, used as h1/title
          description => global intro text
      },
      status => {
          level =>  one of 'error','success','info','warn',
          message => the status message 
      },
      main => {
          Holds content for the main area, depends on page type
      }
      
      
  } 

=head2 Status

Most calls return a key status in the response hash. Subkeys are level and 
message where level is one of 'error','success','info','warn'.

=head2 Forms 

If you have a form, you need to send back the fields requested and the 
parameter given by 'action' (as is). If the input is accepted, you will
get back a new page definition, if the input is not accepted, you will
get ONLY a hash with key 'error' holding a hash with the fieldnames and
a reason what is wrong. Optional is a second key named status.

=head1 Expected Test Cases

=head2 Login Form

Call without a valid session, you will get the description of the login form.
Hardcoded valid login is admin/openxpki - anything else should give an error.
The login currently ends in an empty Welcome page.

=head2 Certificate Search

Call with a valid session (do login - works using cookie magic) and the param
page=certsearch, fill the form as requested, you get back a 'grid' page.


