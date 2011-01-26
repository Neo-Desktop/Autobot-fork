# Auto IRC Bot. An advanced, lightweight and powerful IRC bot.
# Copyright (C) 2010-2011 Xelhua Development Team (doc/CREDITS)
# This program is free software; rights to this code are stated in doc/LICENSE.

# Subroutines for parsing incoming data from IRC.
package Parser::IRC;
use strict;
use warnings;
use API::Std qw(conf_get err awarn);
use API::IRC;

# Raw parsing hash.
our %RAWC = (
	'001'      => \&num001,
	'005'      => \&num005,
	'353'      => \&num353,
	'432'      => \&num432,
	'433'      => \&num433,
	'438'      => \&num438,
	'465'      => \&num465,
	'471'      => \&num471,
	'473'      => \&num473,
	'474'      => \&num474,
	'475'      => \&num475,
	'477'      => \&num477,
	'JOIN'     => \&cjoin,
	'NICK'     => \&nick,
	'PRIVMSG'  => \&privmsg,
);

# Variables for various functions.
our (%got_001, %botnick, %botchans, %csprefix, %chanusers);

# Events.
API::Std::event_add("on_rcjoin");
API::Std::event_add("on_ucjoin");
API::Std::event_add("on_nick");
API::Std::event_add("on_topic");

# Parse raw data.
sub ircparse
{
	my ($svr, $data) = @_;
	
	# Split spaces into @ex.
	my @ex = split(' ', $data);
	
	# Make sure there is enough data.
	if (defined $ex[0] and defined $ex[1]) {
		# If it's a ping...
		if ($ex[0] eq 'PING') {
			# send a PONG.
			Auto::socksnd($svr, "PONG ".$ex[1]);
		}
		else {
			# otherwise, check %RAWC for ex[1].
			if (defined $RAWC{$ex[1]}) {
				&{ $RAWC{$ex[1]} }($svr, @ex);
			}
		}
	}
	
	return 1;
}

###########################
# Raw parsing subroutines #
###########################

# Parse: Numeric:001
# Successful connection.
sub num001
{
	my ($svr, @ex) = @_;
	
	$got_001{$svr} = 1;
	
	# In case we don't get NICK from the server.
	if (defined $botnick{$svr}{newnick}) {
		$botnick{$svr}{nick} = $botnick{$svr}{newnick};
		delete $botnick{$svr}{newnick};
	}
	
	# Modes on connect.
	unless (!conf_get("server:$svr:modes")) {
		my $connmodes = (conf_get("server:$svr:modes"))[0][0];
		API::IRC::umode($svr, $connmodes);
	}
	
	# Identify string.
	unless (!conf_get("server:$svr:idstr")) {
		my $idstr = (conf_get("server:$svr:idstr"))[0][0];
		Auto::socksnd($svr, $idstr);
	}
	
	# Get the auto-join from the config.
	my @cajoin = @{ (conf_get("server:$svr:ajoin"))[0] };
	
	# Join the channels.
	if (!defined $cajoin[1]) {
		# For single-line ajoins.
		my @sajoin = split(',', $cajoin[0]);
		
		API::IRC::cjoin($svr, $_) foreach (@sajoin);
	}
	else {
		# For multi-line ajoins.
		API::IRC::cjoin($svr, $_) foreach (@cajoin);
	}
	
	return 1;
}

# Parse: Numeric:005
# Prefixes.
sub num005
{
	my ($svr, @ex) = @_;
	
	# Find PREFIX.
	foreach my $ex (@ex) {
		if (substr($ex, 0, 7) eq "PREFIX=") {
			# Found.
			my $rpx = substr($ex, 8);
			my ($pm, $pp) = split('\)', $rpx);
			my @apm = split(//, $pm);
			my @app = split(//, $pp);
			foreach my $ppm (@apm) {
				# Store data.
				$csprefix{$svr}{$ppm} = shift(@app);
			}
		}
	}
				
	return 1;
}

# Parse: Numeric:353
# NAMES reply.
sub num353
{
	my ($svr, @ex) = @_;
	
	# Get rid of the colon.
	$ex[5] = substr($ex[5], 1);
	# Delete the old chanusers hash if it exists.
	delete $chanusers{$svr}{$ex[4]} if (defined $chanusers{$svr}{$ex[4]});
	# Iterate through each user.
	for (my $i = 5; $i < scalar(@ex); $i++) {
		my $fi = 0;
		foreach (keys %{ $csprefix{$svr} }) {
			# Check if the user has status in the channel.
			if (substr($ex[$i], 0, 1) eq $csprefix{$svr}{$_}) {
				# He/she does. Lets set that.
				if (defined $chanusers{$svr}{$ex[4]}{lc(substr($ex[$i], 1))}) {
					# If the user has multiple statuses.
					$chanusers{$svr}{$ex[4]}{lc(substr($ex[$i], 1))} .= $_;
				}
				else {
					# Or not.
					$chanusers{$svr}{$ex[4]}{lc(substr($ex[$i], 1))} = $_;
				}
				$fi = 1;
			}
		}
		# They had status, so go to the next user.
		next if $fi;
		# They didn't, set them as a normal user.
		if (!defined $chanusers{$svr}{$ex[4]}{lc($ex[$i])}) {
			$chanusers{$svr}{$ex[4]}{lc($ex[$i])} = 1;
		}
	}
	
	return 1;
}

# Parse: Numeric:432
# Erroneous nickname.
sub num432
{
	my ($svr, undef) = @_;
	
	if ($got_001{$svr}) {
		err(3, "Got error from server[".$svr."]: Erroneous nickname.", 0);
	}
	else {
		err(2, "Got error from server[".$svr."] before 001: Erroneous nickname. Closing connection.", 0);
		API::IRC::quit($svr, "An error occurred.");
	}
	
	delete $botnick{$svr}{newnick} if (defined $botnick{$svr}{newnick});
	
	return 1;
}

# Parse: Numeric:433
# Nickname is already in use.
sub num433
{
	my ($svr, undef) = @_;
	
	if (defined $botnick{$svr}{newnick}) {
		API::IRC::nick($svr, $botnick{$svr}{newnick}."_");
		delete $botnick{$svr}{newnick} if (defined $botnick{$svr}{newnick});
	}
	
	return 1;
}

# Parse: Numeric:438
# Nick change too fast.
sub num438
{
	my ($svr, @ex) = @_;
	
	if (defined $botnick{$svr}{newnick}) {
		API::Std::timer_add("num438_".$botnick{$svr}{newnick}, 1, $ex[11], sub { 
			API::IRC::nick($Parser::IRC::botnick{$svr}{newnick});
			delete $botnick{$svr}{newnick} if (defined $botnick{$svr}{newnick});
		 });
	}
	
	return 1;
}

# Parse: Numeric:465
# You're banned creep!
sub num465
{
	my ($svr, undef) = @_;
	
	err(3, "Banned from ".$svr."! Closing link...", 0);
	
	return 1;
}

# Parse: Numeric:471
# Cannot join channel: Channel is full.
sub num471
{
	my ($svr, (undef, undef, undef, $chan)) = @_;
	
	err(3, "Cannot join channel ".$chan." on ".$svr.": Channel is full.", 0);
	
	return 1;
}

# Parse: Numeric:473
# Cannot join channel: Channel is invite-only.
sub num473
{
	my ($svr, (undef, undef, undef, $chan)) = @_;
	
	err(3, "Cannot join channel ".$chan." on ".$svr.": Channel is invite-only.", 0);
	
	return 1;
}

# Parse: Numeric:474
# Cannot join channel: Banned from channel.
sub num474
{
	my ($svr, (undef, undef, undef, $chan)) = @_;
	
	err(3, "Cannot join channel ".$chan." on ".$svr.": Banned from channel.", 0);
	
	return 1;
}

# Parse: Numeric:475
# Cannot join channel: Bad key.
sub num475
{
	my ($svr, (undef, undef, undef, $chan)) = @_;
	
	err(3, "Cannot join channel ".$chan." on ".$svr.": Bad key.", 0);
	
	return 1;
}

# Parse: Numeric:477
# Cannot join channel: Need registered nickname.
sub num477
{
	my ($svr, (undef, undef, undef, $chan)) = @_;
	
	err(3, "Cannot join channel ".$chan." on ".$svr.": Need registered nickname.", 0);
	
	return 1;
}

# Parse: JOIN
sub cjoin
{
	my ($svr, @ex) = @_;
	my %src = API::IRC::usrc(substr($ex[0], 1));
	
	# Check if this is coming from ourselves.
	if ($src{nick} eq $botnick{$svr}{nick}) {
		# It is. Add channel to array and trigger on_ucjoin.
		unless (defined $botchans{$svr}) {
			@{ $botchans{$svr} } = (substr($ex[2], 1));
		}
		else {
			push(@{ $botchans{$svr} }, substr($ex[2], 1));
		}
		API::Std::event_run("on_ucjoin", ($svr, substr($ex[2], 1)));
	}
	else {
		# It isn't. Trigger on_rcjoin.
		API::Std::event_run("on_rcjoin", ($svr, %src, substr($ex[2], 1)));
	}
	
	return 1;
}

# Parse: NICK
sub nick
{
	my ($svr, ($uex, undef, $nex)) = @_;
	
	my %src = API::IRC::usrc(substr($uex, 1));
	
	# Check if this is coming from ourselves.
	if ($src{nick} eq $botnick{$svr}{nick}) {
		# It is. Update bot nick hash.
		$botnick{$svr}{nick} = $nex;
		delete $botnick{$svr}{newnick} if (defined $botnick{$svr}{newnick});
	}
	else {
		# It isn't. Trigger on_nick.
		API::Std::event_run("on_nick", ($svr, %src, $nex));
	}
	
	return 1;	
}

# Parse: PRIVMSG
sub privmsg
{
	my ($svr, @ex) = @_;
	my %src = API::IRC::usrc(substr($ex[0], 1));

	my $cprefix = (conf_get("fantasy_pf"))[0][0];
	my $rprefix = substr($ex[3], 1, 1);
	my $cmd = uc(substr($ex[3], 2));
	my (@argv);
	for (my $i = 4; $i < scalar(@ex); $i++) {
		push(@argv, $ex[$i]);
	}
	# Check if it's to a channel or to us.
	if (lc($ex[2]) eq lc($botnick{$svr}{nick})) {
		# It is coming to us in a private message.
		if (defined $API::Std::CMDS{$cmd}) {
			if ($API::Std::CMDS{$cmd}{lvl} == 1 or $API::Std::CMDS{$cmd}{lvl} == 2) {
				eval {
					&{ $API::Std::CMDS{$cmd}{sub} }($svr, %src, @argv);
				};
			}
		}
	}
	else {
		# It is coming to us in a channel message.
		$src{chan} = $ex[2];
		if (defined $API::Std::CMDS{$cmd}) {
			if ($API::Std::CMDS{$cmd}{lvl} == 0 or $API::Std::CMDS{$cmd}{lvl} == 2) {
				eval {
					&{ $API::Std::CMDS{$cmd}{sub} }($svr, %src, @argv);
				};
			}
		}
	}
	
	return 1;
}

# Parse: TOPIC
sub topic
{
	my ($svr, @ex) = @_;
	my %src = API::IRC::usrc(substr($ex[0], 1));
	
	# Ignore it if it's coming from us.
	if (lc($src{nick}) ne lc($botnick{$svr}{nick})) {
		$src{chan} = $ex[2];
		my (@argv);
		$argv[0] = substr($ex[3], 1);
		if (defined $ex[4]) {
			for (my $i = 4; $i < scalar(@ex); $i++) {
				push(@argv, $ex[$i]);
			}
		}
		API::Std::event_run("on_topic", ($svr, %src, @argv));
	}
	
	return 1;
}


1;