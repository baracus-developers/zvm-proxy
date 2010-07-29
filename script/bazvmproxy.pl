#!/usr/bin/perl

use strict;
use warnings;
use File::Basename;
use Baracus::zVMProxy qw(:all);

run(basename($0, '.pl'));
