#!/usr/bin/perl

## Threaded SSH Command Runner. This script is intended to run a remote command
## via SSH on many servers in a short amount of time. Suppose you need to quickly
## modify a file in the same way on 1000+ servers in an emergency situation? 
## This is your answer (hopefully you are using Puppet for anything other than
## an emergency). In order to use this script, you need to change the $SSH_COMMAND
## variable in the CONFIG section to suit your needs. You may also tweak the 
## $MAX_THREADS variable if you're feeling lucky. 

## Created by Robby Dyer 

use Getopt::Std;
use Net::OpenSSH;
use threads;
use threads::shared;

##CONFIG
our $SSH_COMMAND="";
our $MAX_THREADS=25;
our $MAX_TICKS=50; # For the status bar- character width of the status bar
our $STATUS_PRINT_RATE=25;  # For the status bar- rate it which the status bar is updated
#############


sub getInput ## Convert list of servers from file to array.
{
	my $input_filename=shift;
	my @server_list;
	open(SERVERLIST,"< $input_filename") || die ("error opening file: $input_filename");
	while(my $host = <SERVERLIST>)
	{	
		chomp $host;
		push(@server_list,$host);
	}

	return @server_list;
}

sub iterateHosts ## Create and manage threads
{
	my $list_ref=shift @_;
    my $current_threads=0;
    my @threads;
    my $completed=0;
	my @server_list=@$list_ref;
    my $total=@server_list;
    printStatus('',$completed,$total);
	foreach my $host (@server_list)
	{
		chomp $host;
        while($current_threads >= $MAX_THREADS)
        {
            foreach (@threads)
            {
                if($_->is_joinable())
                {
                    $_->join();
                    $current_threads--;
                    $completed++;
                    if(($completed % $STATUS_PRINT_RATE) == 0) { printStatus($host,$completed,$total);} # Let's not run this too often
                }
            }
        }
        
        ## create a new thread
        $current_threads++;
        my $t=threads->new(\&doWork,$host);
        push(@threads,$t);
	}

    # Join any remaining threads
    foreach (@threads)
    {
        if($_->is_joinable() or $_->is_running())
        {
            $_->join();
            $completed++;
            printStatus("",$completed,$total);
        }
    }
    
    print "All threads done\n";

	#generateOutput($error);
}

sub printStatus
{
    my $host=shift;
    my $completed=shift;
    my $total=shift;

# Clear the screen. This won't work unless its a Nix box

    system("clear");
    print "Recently Queued host: $host\n\n";
    my $percentage=int(($completed/$total)*100);
    print " $percentage"."% Complete\n";
    print "|";
    my $symbol="-";
    my $current=$completed/$total;
    my $ticks=int($current*$MAX_TICKS);
    for ($i=0;$i<$ticks;$i++)
    {   
        print $symbol;
    }
    print ">";
    for ($i=0;$i<($MAX_TICKS-$ticks);$i++)
    {   
        print " ";
    }
    
    print "|\n\n";

}

sub doWork ## Each thread will call this function. Actual work is done here. 
{
    my $host=shift;
    my $ssh=Net::OpenSSH->new($host,user=>$ssh_user,password=>$ssh_password,timeout=>5,master_stderr_discard=>1);
    if($ssh->error or $?!=0){ ## If we can't login to this host, then bail on the thread. 
        generateOutput("Could not SSH:$host\n");
        return;
    }
    my $out;    
    my $err;

    ($out,$err)=$ssh->capture2($SSH_COMMAND);

    generateOutput($host.",".$out."\n");
    return;
}

sub generateOutput ## Generate output file
{
    my $error=shift;
	open(ERROR,">> $output_file");
	flock(ERROR,2);
	print ERROR "$error";
	close ERROR;
}


### MAIN #####
our $check_hour=1;
our $debug=0;
my %options;
getopts('f:u:p:o:d',\%options);

if(!exists($options{f})){ print "please specify an input file of servers (newline delimited)\n"; die; }
if(!exists($options{u})){ print "please specify an SSH user\n"; die; }
our $ssh_password;
if(!exists($options{p}))
{
	print "SSH Password: ";
        system('stty','-echo');
        chop($password=<STDIN>);
        system('stty','echo');
        print "\n";
	$ssh_password=$password;
}
else
{
	$ssh_password=$options{p};
}

our $ssh_user=$options{u};
if(exists($options{d})){$debug=1;}

my $filekey=time;
chomp $filekey;
our $output_file="SSHOUT.err";
`>$output_file`;

my @full_server_list=getInput($options{f});

iterateHosts(\@full_server_list,$output_file);
