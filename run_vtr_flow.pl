#!/usr/bin/perl
###################################################################################
# This script runs the VTR flow for a single benchmark circuit and architecture
# file.
#
# Usage:
#	run_vtr_flow.pl <circuit_file> <architecture_file> [OPTIONS]
#
# Parameters:
# 	circuit_file: Path to the input circuit file (verilog, blif, etc)
#   architecture_file: Path to the architecture file (.xml)
#
# Options:
# 	-starting_stage <stage>: Start the VTR flow at the specified stage.
#								Acceptable values: odin, abc, script, vpr.
#								Default value is odin.
#   -ending_stage <stage>: End the VTR flow at the specified stage. Acceptable
#								values: odin, abc, script, vpr. Default value is
#								vpr.
# 	-keep_intermediate_files: Do not delete the intermediate files.
#
#   -temp_dir <dir>: Directory used for all temporary files
###################################################################################

use strict;
use Cwd;
use File::Spec;
use POSIX;
use File::Copy;
use FindBin;
use File::Which;
use File::Basename;
use Config;


use Carp;
$SIG{ __DIE__ } = sub { Carp::confess( @_ ) };

use lib "$FindBin::Bin/perl_libs/XML-TreePP-0.41/lib";
use XML::TreePP;

# check the parametes.  Note PERL does not consider the script itself a parameter.
my $number_arguments = @ARGV;   # 装参数：(<circuit_file> <architecture_file> [OPTIONS])
if ( $number_arguments < 2 ) {
	print(
		"usage: run_vtr_flow.pl <circuit_file> <architecture_file> [OPTIONS]\n"
	);
	exit(-1);
}

# Get Absoluate Path of 'vtr_flow
Cwd::abs_path($0) =~ m/(.*\/vtr_flow)\//;
my $vtr_flow_path = $1;
# my $vtr_flow_path = "./vtr_flow";

sub stage_index;
sub file_ext_for_stage;
sub expand_user_path;
sub file_find_and_replace;
sub xml_find_LUT_Kvalue;
sub xml_find_mem_size;

my $temp_dir = "";

my $stage_idx_odin      = 1;
my $stage_idx_abc       = 2;
my $stage_idx_ace       = 3;
my $stage_idx_prevpr    = 4;
my $stage_idx_vpr       = 5;
my $stage_idx_bitstream = 6;

my $circuit_file_path      = expand_user_path( shift(@ARGV) ); # (<architecture_file> [OPTIONS]) ，返回：<circuit_file>
my $architecture_file_path = expand_user_path( shift(@ARGV) ); # ([OPTIONS]) ，返回：<architecture_file>
my $sdc_file_path = "\"\"";

my $token;
my $ext;
my $starting_stage          = stage_index("odin");
my $ending_stage            = stage_index("bitstream");
my $vpr_stage              = "";                    # 新增
my $keep_intermediate_files = 1;
my $has_memory              = 1;
my $timing_driven           = "on";
my $min_chan_width          = 18; 
my $lut_size                = -1;
my $vpr_cluster_seed_type   = "";
my $tech_file               = "";
my $do_power                = 0;
my $check_equivalent		= "off";
my $gen_postsynthesis_netlist 	= "off";
my $seed			= 1;
my $min_hard_adder_size		= 4;
my @vpr_options             = qw(--allow_unrelated_clustering off);
my $vpr_fix_pins            = "random";
my $yosys_script            = "";
my $yosys_script_default    = "yosys.ys";
my $yosys_models            = "";
my $yosys_models_default    = "yosys_models.v";
my $yosys_abc_script        = "";
my $yosys_abc_script_default = "abc_vtr.rc";
my $abc_lut_file            = "abc_lut6.lut";

while ( $token = shift(@ARGV) ) { 
#() 返回第一个选项，$token="-starting_stage"  
	if ( $token eq "-sdc_file" ) {
		$sdc_file_path = expand_user_path( shift(@ARGV) );
	}
	elsif ( $token eq "-starting_stage" ) {
		$starting_stage = stage_index( shift(@ARGV) ); # odin,  1
	}
	elsif ( $token eq "-ending_stage" ) {
		$ending_stage = stage_index( shift(@ARGV) ); # bitstream, 6
	}
	# 新增=======================================
	elsif ( $token eq "-vpr_stage" ) {
		$vpr_stage = shift(@ARGV);  # --pack
	}
	# ================================================
	elsif ( $token eq "-keep_intermediate_files" ) {
		$keep_intermediate_files = 1;
	}
	elsif ( $token eq "-no_mem" ) {
		$has_memory = 0;
	}
	elsif ( $token eq "-no_timing" ) {
		$timing_driven = "off";
	}
	elsif ( $token eq "-vpr_route_chan_width" ) {
		$min_chan_width = shift(@ARGV);
	}
	elsif ( $token eq "-lut_size" ) {
		$lut_size = shift(@ARGV);
	}
	elsif ( $token eq "-vpr_cluster_seed_type" ) {
		$vpr_cluster_seed_type = shift(@ARGV);
	}
	elsif ( $token eq "-temp_dir" ) {
		$temp_dir = shift(@ARGV);
	}
	elsif ( $token eq "-cmos_tech" ) {
		$tech_file = shift(@ARGV);
	}
	elsif ( $token eq "-power" ) {
		$do_power = 1;
	}
	elsif ( $token eq "-check_equivalent" ) {
		$check_equivalent = "on";
	}
	elsif ( $token eq "-gen_postsynthesis_netlist" ) {
		$gen_postsynthesis_netlist = "on";
	}
	elsif ( $token eq "-seed" ) {
		$seed = shift(@ARGV);
	}
	elsif ( $token eq "-min_hard_adder_size" ) {
		$min_hard_adder_size = shift(@ARGV);
	}
	elsif ( $token eq "-yosys" ) {
		$yosys_script = $yosys_script_default;
	}
	elsif ( $token eq "-yosys_script" ) {
		$yosys_script = shift(@ARGV);
	}
	elsif ( $token eq "-yosys_models" ) {
		$yosys_models = shift(@ARGV);
	}
	elsif ( $token eq "-yosys_abc_script" ) {
		$yosys_abc_script = shift(@ARGV);
	}
	elsif ( $token eq "-abc_lut" ) {
		$abc_lut_file = shift(@ARGV);
	}
	elsif ( $token eq "-vpr_options" ) {
		push(@vpr_options, split(' ', shift(@ARGV)));
	}
	elsif ($token eq "-vpr_fix_pins") {
		$vpr_fix_pins = shift(@ARGV);
	}
	else {
		die "Error: Invalid argument ($token)\n";
	}

	if ( $starting_stage == -1 or $ending_stage == -1 ) {
		die
		  "Error: Invalid starting/ending stage name (start $starting_stage end $ending_stage).\n";
	}
}

if ( $ending_stage < $starting_stage ) {
	die "Error: Ending stage is before starting stage.";
}
if ($do_power) {
	if ( $tech_file eq "" ) {
		die "A CMOS technology behavior file must be provided.";
	}
	elsif ( not -r $tech_file ) {
		die "The CMOS technology behavior file ($tech_file) cannot be opened.";
	}
	$tech_file = Cwd::abs_path($tech_file);
}

if ( $vpr_cluster_seed_type eq "" ) {
	if ( $timing_driven eq "off" ) {
		$vpr_cluster_seed_type = "max_inputs";
	}
	else {
		$vpr_cluster_seed_type = "timing";
	}
}

# Test for file existance
( -f $circuit_file_path )
  or die "Circuit file not found ($circuit_file_path)";
( -f $architecture_file_path )
  or die "Architecture file not found ($architecture_file_path)";

if ( $temp_dir eq "" ) {
	$temp_dir = basename($architecture_file_path,".xml")."/".basename($circuit_file_path,".v");
}
if ( !-d $temp_dir ) {
	system "mkdir -p $temp_dir";
}
-d $temp_dir or die "Could not make temporary directory ($temp_dir)\n";
if ( !( $temp_dir =~ /.*\/$/ ) ) {
	$temp_dir = $temp_dir . "/";
}

my $timeout      = 10 * 24 * 60 * 60;         # 10 day execution timeout
my $results_path = "${temp_dir}output.txt";

my $error;
my $error_code = 0;

my $arch_param;
my $cluster_size;
my $inputs_per_cluster = -1;


if ( !-e $sdc_file_path ) {
	# open( OUTPUT_FILE, ">$sdc_file_path" ); 
	# close ( OUTPUT_FILE );
	my $sdc_file_path;
}

my $vpr_path;
if ( $stage_idx_vpr >= $starting_stage and $stage_idx_vpr <= $ending_stage ) {
	$vpr_path = "$vtr_flow_path/../vpr/vpr";
	( -r $vpr_path or -r "${vpr_path}.exe" )
	  or die "Cannot find vpr exectuable ($vpr_path)";

  	if ($vpr_fix_pins ne "random") {
		( -r $vpr_fix_pins ) or die "Cannot find $vpr_fix_pins!";
		copy($vpr_fix_pins, $temp_dir);
		$vpr_fix_pins = basename($vpr_fix_pins);
	}
}

my $odin2_path;
my $odin_config_file_name;
my $odin_config_file_path;
my $yosys_path;
my $yosys_config_file_name;
my $yosys_config_file_path;
my $yosys_abc_script_file_path;

my $models_file_path_default;
my $models_file_path;
my $abc_rc_path;
my $yosys_abc_script_path;

if (    $stage_idx_odin >= $starting_stage
	and $stage_idx_odin <= $ending_stage )
{
	if ($yosys_script eq "") {
		$odin2_path = "$vtr_flow_path/../ODIN_II/odin_II.exe";
		( -e $odin2_path )
			or die "Cannot find ODIN_II executable ($odin2_path)";

		$odin_config_file_name = "basic_odin_config_split.xml";

		$odin_config_file_path = "$vtr_flow_path/misc/$odin_config_file_name";
		( -e $odin_config_file_path )
			or die "Cannot find ODIN config template ($odin_config_file_path)";

		$odin_config_file_name = "odin_config.xml";
		my $odin_config_file_path_new = "$temp_dir" . "odin_config.xml";
		copy( $odin_config_file_path, $odin_config_file_path_new );
		$odin_config_file_path = $odin_config_file_path_new;
	}
	else
	{
		$yosys_path = "$vtr_flow_path/../yosys/yosys";
		( -e $yosys_path )
			or die "Cannot find Yosys executable ($yosys_path)";

		$yosys_config_file_name = $yosys_script;
		$yosys_config_file_path = "$vtr_flow_path/misc/$yosys_config_file_name";
		( -e $yosys_config_file_path )
			or die "Cannot find Yosys script ($yosys_config_file_path)";

		my $yosys_config_file_path_new = "$temp_dir" . "$yosys_config_file_name";
		copy( $yosys_config_file_path, $yosys_config_file_path_new );
		$yosys_config_file_path = $yosys_config_file_path_new;

		my $tech_file_name;
		$tech_file_name = "single_port_ram.v";
		copy( "$vtr_flow_path/misc/$tech_file_name", "$temp_dir"."$tech_file_name" );
		$tech_file_name = "dual_port_ram.v";
		copy( "$vtr_flow_path/misc/$tech_file_name", "$temp_dir"."$tech_file_name" );
		$tech_file_name = "adder.v";
		copy( "$vtr_flow_path/misc/$tech_file_name", "$temp_dir"."$tech_file_name" );
		$tech_file_name = "multiply.v";
		copy( "$vtr_flow_path/misc/$tech_file_name", "$temp_dir"."$tech_file_name" );
		$tech_file_name = "xadder.v";
		copy( "$vtr_flow_path/misc/$tech_file_name", "$temp_dir"."$tech_file_name" );
		$tech_file_name = "bufgctrl.v";
		copy( "$vtr_flow_path/misc/$tech_file_name", "$temp_dir"."$tech_file_name" );
		$tech_file_name = "adder2xadder.v";
		copy( "$vtr_flow_path/misc/$tech_file_name", "$temp_dir"."$tech_file_name" );

		my $models_file_name = $yosys_models_default;
		$models_file_path_default = "$temp_dir"."$models_file_name";
		copy( "$vtr_flow_path/misc/$models_file_name", "$models_file_path_default" );

		$models_file_name = $yosys_models;
		if ($models_file_name ne "") {
			$models_file_path = "$temp_dir"."$models_file_name";
			copy( "$vtr_flow_path/misc/$models_file_name", "$models_file_path" );
		}

		if ($yosys_abc_script eq "") { 
			$yosys_abc_script = $yosys_abc_script_default;
		}
		$yosys_abc_script_path = "$temp_dir"."$yosys_abc_script";
		copy( "$vtr_flow_path/misc/$yosys_abc_script", $yosys_abc_script_path );
	}
}

my $abc_path;
$abc_rc_path = "$vtr_flow_path/../abc_with_bb_support/abc.rc";
( -e $abc_rc_path ) or die "Cannot find ABC RC file ($abc_rc_path)";
copy( $abc_rc_path, $temp_dir );

my $abc_lut_path = "$vtr_flow_path/misc/$abc_lut_file";
( -e $abc_lut_path ) or die "Cannot find ABC LUT file ($abc_lut_path)";
copy( $abc_lut_path, $temp_dir );

$abc_path = "$vtr_flow_path/../abc_with_bb_support/abc";
if ( $stage_idx_abc >= $starting_stage and $stage_idx_abc <= $ending_stage ) {
	( -e $abc_path or -e "${abc_path}.exe" )
	  or die "Cannot find ABC executable ($abc_path)";
}

my $ace_path;
if ( $stage_idx_ace >= $starting_stage and $stage_idx_ace <= $ending_stage and $do_power) {
	$ace_path = "$vtr_flow_path/../ace2/ace";
	( -e $ace_path or -e "${ace_path}.exe" )
	  or die "Cannot find ACE executable ($ace_path)";
}


my $bitstream_path = "$vtr_flow_path/../bnpr2xdl/bnpr2xdl";
my ($xdl_path, $par_path, $trce_path, $bitgen_path);
my $arch = basename($architecture_file_path,".xml");
if ( $stage_idx_bitstream >= $starting_stage and $stage_idx_bitstream <= $ending_stage ) {
	(-e $bitstream_path) or die "Warning: Cannot find $bitstream_path. Please run \"make\" again.";

	$xdl_path = which("xdl") or die "Cannot find xdl exectuable on \$PATH\n";

	$trce_path = which("trce") or die "Cannot find trce exectuable on \$PATH\n";

	$bitgen_path = which("bitgen") or die "Cannot find bitgen exectuable on \$PATH\n";
}

# Get circuit name (everything up to the first '.' in the circuit file)
my ( $vol, $path, $circuit_file_name ) =
  File::Spec->splitpath($circuit_file_path);
$circuit_file_name =~ m/(.*)[.].*?/;
my $benchmark_name = $1;

# Get architecture name
$architecture_file_path =~ m/.*\/(.*?.xml)/;
my $architecture_file_name = $1;

$architecture_file_name =~ m/(.*).xml$/;
my $architecture_name = $1;
print "$architecture_name/$benchmark_name...\n";

# Get Memory Size
my $mem_size = -1;
my $line;
my $in_memory_block;
my $in_mode;

# Read arch XML
my $tpp      = XML::TreePP->new();
my $xml_tree = $tpp->parsefile($architecture_file_path);

# Get lut size
if ( $lut_size < 1 ) {
	$lut_size = xml_find_LUT_Kvalue($xml_tree);
	if ( $lut_size < 1 ) {
		print "failed: cannot determine arch LUT k-value";
		$error_code = 1;
	}
}
print "LUT size: $lut_size\n";

# Get memory size
$mem_size = xml_find_mem_size($xml_tree);
print "MEM size: $mem_size\n";
print "Min Hard Adder size: $min_hard_adder_size\n";

my $odin_output_file_name =
  "$benchmark_name" . file_ext_for_stage($stage_idx_odin);
my $odin_output_file_path = "$temp_dir$odin_output_file_name";

my $abc_output_file_name =
  "$benchmark_name" . file_ext_for_stage($stage_idx_abc);
my $abc_output_file_path = "$temp_dir$abc_output_file_name";

my $ace_output_blif_name =
  "$benchmark_name" . file_ext_for_stage($stage_idx_ace);
my $ace_output_blif_path = "$temp_dir$ace_output_blif_name";

my $ace_output_act_name = "$benchmark_name" . ".act";
my $ace_output_act_path = "$temp_dir$ace_output_act_name";

my $prevpr_output_file_name =
  "$benchmark_name" . file_ext_for_stage($stage_idx_prevpr);
my $prevpr_output_file_path = "$temp_dir$prevpr_output_file_name";

my $vpr_route_output_file_name = "$benchmark_name.route";
my $vpr_route_output_file_path = "$temp_dir$vpr_route_output_file_name";

#system "cp $abc_rc_path $temp_dir";
#system "cp $architecture_path $temp_dir";
#system "cp $circuit_path $temp_dir/$benchmark_name" . file_ext_for_stage($starting_stage - 1);
#system "cp $odin2_base_config"

my $architecture_file_path_new = "$temp_dir$architecture_file_name";
copy( $architecture_file_path, $architecture_file_path_new );
my $architecture_file_path_orig = $architecture_file_path;
$architecture_file_path = $architecture_file_path_new;

my $circuit_file_path_new =
  "$temp_dir$benchmark_name" . file_ext_for_stage(0);
copy( $circuit_file_path, $circuit_file_path_new );
$circuit_file_path = $circuit_file_path_new;

# Call executable and time it
my $StartTime = time;
my $q         = "not_run";

#################################################################################
################################## ODIN #########################################
#################################################################################

if ( $starting_stage <= $stage_idx_odin and !$error_code ) {

	unlink "$odin_output_file_path";
	if ($yosys_script eq "") {
		#system "sed 's/XXX/$benchmark_name.v/g' < $odin2_base_config > temp1.xml";
		#system "sed 's/YYY/$arch_name/g' < temp1.xml > temp2.xml";
		#system "sed 's/ZZZ/$odin_output_file_path/g' < temp2.xml > temp3.xml";
		#system "sed 's/PPP/$mem_size/g' < temp3.xml > circuit_config.xml";

		file_find_and_replace( $odin_config_file_path, "XXX", $circuit_file_name );
		file_find_and_replace( $odin_config_file_path, "YYY",
			$architecture_file_name );
		file_find_and_replace( $odin_config_file_path, "ZZZ",
			$odin_output_file_name );
		file_find_and_replace( $odin_config_file_path, "PPP", $mem_size );
		file_find_and_replace( $odin_config_file_path, "AAA", $min_hard_adder_size );

		if ( !$error_code ) {
			$q =
			&system_with_timeout( "$odin2_path", "odin.out", $timeout, $temp_dir,
				"-c", $odin_config_file_name );

			if ( -e $odin_output_file_path ) {
				if ( !$keep_intermediate_files ) {
					system "rm -f ${temp_dir}*.dot";
					system "rm -f ${temp_dir}*.v";
					system "rm -f $odin_config_file_path";
				}
			}
			else {
				print "failed: odin";
				$error_code = 1;
			}
		}
	}
	else {
		file_find_and_replace( $yosys_config_file_path, "XXX", $circuit_file_name );
		file_find_and_replace( $yosys_config_file_path, "ZZZ",
			$odin_output_file_name );
		#file_find_and_replace( $yosys_config_file_path, "LUTSIZE", $lut_size );
		file_find_and_replace( $yosys_config_file_path, "ABCEXE", $abc_path );
		file_find_and_replace( $yosys_config_file_path, "ABCSCRIPT", $yosys_abc_script );

		file_find_and_replace( $yosys_abc_script_path, "ABCLUT", $abc_lut_file );

		file_find_and_replace( $models_file_path_default, "PPP", $mem_size );
		file_find_and_replace( $models_file_path_default, "AAA", $min_hard_adder_size );
		if ($models_file_path ne "") {
			file_find_and_replace( $models_file_path, "PPP", $mem_size );
			file_find_and_replace( $models_file_path, "AAA", $min_hard_adder_size );
		}

		if ( !$error_code ) {
			$q =
			&system_with_timeout( "$yosys_path", "yosys.out", $timeout, $temp_dir,
				"-v 2", $yosys_config_file_name );

			if ( -e $odin_output_file_path ) {
				if ( !$keep_intermediate_files ) {
					system "rm -f ${temp_dir}*.dot";
					system "rm -f ${temp_dir}*.v";
					system "rm -f $odin_config_file_path";
				}
			}
			else {
				print "failed: yosys";
				$error_code = 1;
			}
		}

	}
}

#################################################################################
################################## ABC ##########################################
#################################################################################
if (    $starting_stage <= $stage_idx_abc
	and $ending_stage >= $stage_idx_abc
	and !$error_code )
{
	if ($yosys_script eq "") {
		# EH: Replace all .subckt adder with .subckt xadder, 
		# with XOR and AND pushed into soft-logic
		my $abc_input_file_name = "$benchmark_name" . ".xadder" . file_ext_for_stage($stage_idx_odin);
		my $abc_input_file_path = "$temp_dir$abc_input_file_name";

		my $adder_model = <<'EOF';
(\.model adder
\.inputs\s+a(\[0\])?\s+b(\[0\])?\s+cin(\[0\])?
\.outputs\s+cout(\[0\])?\s+sumout(\[0\])?)
\.blackbox
\.end
EOF
		my $xadder_model = <<'EOF';
\1
.names a\2 b\3 a_xor_b
01 1
10 1
.names a\2 b\3 a_and_b
11 1
.subckt xadder a_xor_b=a_xor_b a_and_b=a_and_b cin=cin\4 cout=cout\5 sumout=sumout\6
.end

.model xadder
.inputs a_xor_b a_and_b cin
.outputs cout sumout
.blackbox
.end
EOF
		unlink "$abc_input_file_path";
		copy( $odin_output_file_path, $abc_input_file_path );
		&system_with_timeout("/usr/bin/perl", "perl.out", $timeout, $temp_dir, 
			"-0777", "-p", "-i", "-e", "s/$adder_model/$xadder_model/smg", $abc_input_file_name);


		unlink "$abc_output_file_path";
		$q = &system_with_timeout( $abc_path, "abc.out", $timeout, $temp_dir, "-c",
			"read $abc_input_file_name; read_lut $abc_lut_file; time; resyn; resyn2; if -K $lut_size; time; scleanup; time; scleanup; time; scleanup; time; scleanup; time; scleanup; time; scleanup; time; scleanup; time; scleanup; time; scleanup; time; print_stats; write_hie $abc_input_file_name $abc_output_file_name"
		);
	}
	else
	{
		unlink "$abc_output_file_path";
		$q = &system_with_timeout( $abc_path, "abc.out", $timeout, $temp_dir, "-c",
			"read $odin_output_file_name; print_stats; write_hie $odin_output_file_name $abc_output_file_name"
		);
	}

	if ( -e $abc_output_file_path ) {

		#system "rm -f abc.out";
		if ( !$keep_intermediate_files ) {
			system "rm -f $odin_output_file_path";
			system "rm -f ${temp_dir}*.rc";
		}
	}
	else {
		print "failed: abc";
		$error_code = 1;
	}
}

#################################################################################
################################## ACE ##########################################
#################################################################################
if (    $starting_stage <= $stage_idx_ace
	and $ending_stage >= $stage_idx_ace
	and $do_power
	and !$error_code )
{
	$q = &system_with_timeout(
		$ace_path, "ace.out",             $timeout, $temp_dir,
		"-b",      $abc_output_file_name, "-n",     $ace_output_blif_name,
		"-o",      $ace_output_act_name
	);

	if ( -e $ace_output_blif_path ) {
		if ( !$keep_intermediate_files ) {
			system "rm -f $abc_output_file_path";
			#system "rm -f ${temp_dir}*.rc";
		}
	}
	else {
		print "failed: ace";
		$error_code = 1;
	}
}

#################################################################################
################################## PRE-VPR ######################################
#################################################################################
if (    $starting_stage <= $stage_idx_prevpr
	and $ending_stage >= $stage_idx_prevpr
	and !$error_code )
{
	my $prevpr_success   = 1;
	my $prevpr_input_blif_path;
	if ($do_power) {
		$prevpr_input_blif_path = $ace_output_blif_path; 
	} else {
		$prevpr_input_blif_path = $abc_output_file_path;
	}
	
	if ($yosys_script eq "") {
		# EH: Scan all .latch -es for clocks
		# Add a BUFGCTRL for each clock found
		open (my $fin, $prevpr_input_blif_path) or die ("Could not open $prevpr_input_blif_path");
		open (my $fout, ">$prevpr_output_file_path") or die ("Could not open $prevpr_output_file_path");
		my %clks;
		while (my $line = <$fin>) {
			chomp $line;
			$line =~ m/(\s*)\.latch(\s+)([^ ]+)(\s+)([^ ]+)(\s+)([^ ]+)(\s+)([^ ]+)(\s+)([^ ]+)$/;
			if ($9) {
				$clks{$9} = 1;
			}
			foreach my $clk (keys %clks) {
				$line =~ s/\Q$clk /${clk}_BUFG /g;
			}
			print $fout "$line\n";
		}
		close $fin;
		if (keys %clks) {
			print $fout "\n";
			foreach my $clk (keys %clks) {
				print $fout ".subckt bufgctrl i[0]=$clk i[1]=unconn s[0]=unconn s[1]=unconn ce[0]=unconn ce[1]=unconn ignore[0]=unconn ignore[1]=unconn o[0]=$clk"."_BUFG\n";
			}
			print $fout "\n";
			print $fout ".model bufgctrl\n";
			print $fout ".inputs i[0] i[1] s[0] s[1] ce[0] ce[1] ignore[0] ignore[1]\n";
			print $fout ".outputs o[0]\n";
			print $fout ".blackbox\n";
			print $fout ".end\n";
		}
		close $fout;
	}
	else {
		copy($prevpr_input_blif_path, $prevpr_output_file_path);
	}

	if ($prevpr_success) {
		if ( !$keep_intermediate_files ) {
			system "rm -f $prevpr_input_blif_path";
		}
	}
	else {
		print "failed: prevpr";
		$error_code = 1;
	}
}

#################################################################################
################################## VPR ##########################################
#################################################################################

if ( $starting_stage <= $stage_idx_vpr 
	and $ending_stage >= $stage_idx_vpr 
	and !$error_code ) 
{
	(my $rrg_file_path = File::Spec->rel2abs($architecture_file_path_orig)) =~ s{\.[^.]+$}{.rrg.gz};
	(-e "$rrg_file_path") or die("$rrg_file_path does not exist!");
	unless(-e "$temp_dir/".basename($rrg_file_path)) {
		symlink($rrg_file_path, "$temp_dir/".basename($rrg_file_path)) or die;
	}

	my @vpr_power_args;

	if ($do_power) {
		push( @vpr_power_args, "--power" );
		push( @vpr_power_args, "--tech_properties" );
		push( @vpr_power_args, "$tech_file" );
	}
	if ( $min_chan_width < 0 ) {
		$q = &system_with_timeout(
			$vpr_path,                    "vpr.out",
			$timeout,                     $temp_dir,
			$architecture_file_name,      "$benchmark_name",
			"--blif_file",				  "$prevpr_output_file_name",
			"--timing_analysis",          "$timing_driven",
			"--timing_driven_clustering", "$timing_driven",
			"--cluster_seed_type",        "$vpr_cluster_seed_type",
			"--sdc_file", 				  "$sdc_file_path",
			"--seed",			 		  "$seed",
			@vpr_options
			
		);
		if ( $timing_driven eq "on" ) {
			# Critical path delay is nonsensical at minimum channel width because congestion constraints completely dominate the cost function.
			# Additional channel width needs to be added so that there is a reasonable trade-off between delay and area
			# Commercial FPGAs are also desiged to have more channels than minimum for this reason

			# Parse out min_chan_width
			if ( open( VPROUT, "<${temp_dir}vpr.out" ) ) {
				undef $/;
				my $content = <VPROUT>;
				close(VPROUT);
				$/ = "\n";    # Restore for normal behaviour later in script

				if ( $content =~ m/(.*Error.*)/i ) {
					$error = $1;
				}

				if ( $content =~
					/Best routing used a channel width factor of (\d+)/m )
				{
					$min_chan_width = $1;
				}
			}

			$min_chan_width = ( $min_chan_width * 1.3 );
			$min_chan_width = floor($min_chan_width);
			if ( $min_chan_width % 2 ) {
				$min_chan_width = $min_chan_width + 1;
			}

			if ( -e $vpr_route_output_file_path ) {
				system "rm -f $vpr_route_output_file_path";
				$q = &system_with_timeout(
					$vpr_path,               "vpr.crit_path.out",
					$timeout,                $temp_dir,
					$architecture_file_name, "$benchmark_name",
					"--route",
					"--blif_file",           "$prevpr_output_file_name",
					"--route_chan_width",    "$min_chan_width",
					"--cluster_seed_type",   "$vpr_cluster_seed_type",
					"--max_router_iterations", "100",
					           @vpr_power_args,
					"--gen_postsynthesis_netlist", "$gen_postsynthesis_netlist",
					"--sdc_file",			 "$sdc_file_path"
				);
			}
		}
	}
	else {
		if($vpr_stage eq "") {  # 命令行无参数：-vpr_stage   新增====================
			$q = &system_with_timeout($vpr_path, "vpr.out", $timeout, $temp_dir,
				$architecture_file_name,      
				"$benchmark_name", "--blif_file", "$prevpr_output_file_name",
				"--timing_analysis",          "$timing_driven",
				"--timing_driven_clustering", "$timing_driven",
				"--route_chan_width",         "$min_chan_width",
				#                  "--cluster_seed_type",
				#"$vpr_cluster_seed_type",     @vpr_power_args,
				#"--gen_postsynthesis_netlist", "$gen_postsynthesis_netlist",
				#"--sdc_file",		       "$sdc_file_path",
				#"--seed",		       "$seed",
				#"--fix_pins",		       "$vpr_fix_pins",
				@vpr_options
			);
		}
		else { # 命令行有参数：-vpr_stage pack ，此时 $vpr_stage="pack" ========================
			$q = &system_with_timeout(
				$vpr_path,                    "$vpr_stage.out",
				$timeout,                     $temp_dir,
				$architecture_file_name,      "$benchmark_name",
				"--blif_file",                "$prevpr_output_file_name",
				"--timing_analysis",          "$timing_driven",
				"--timing_driven_clustering", "$timing_driven",
				"--route_chan_width",         "$min_chan_width",
				                # "--cluster_seed_type",
				#"$vpr_cluster_seed_type",     @vpr_power_args,
				#"--gen_postsynthesis_netlist", "$gen_postsynthesis_netlist",
				#"--sdc_file",			"$sdc_file_path",
				#"--seed",			"$seed",
				#"--fix_pins",			"$vpr_fix_pins",
				@vpr_options,                   "--$vpr_stage"      # 新增参数：$vpr_stage
			);
		}
	}
	  					
	if (
		-e $vpr_route_output_file_path and  # 生成.route文件且vpr成功执行
		$q eq "success")
	{
		if($check_equivalent eq "on") { # 默认off
			if($abc_path eq "") {
				$abc_path = "$vtr_flow_path/../abc_with_bb_support/abc";
			}
			$q = &system_with_timeout($abc_path, 
							"equiv.out",
							$timeout,
							$temp_dir,
							"-c", 
							"cec $prevpr_output_file_name post_pack_netlist.blif;sec $prevpr_output_file_name post_pack_netlist.blif"
			);
		}
		if (! $keep_intermediate_files)
		{
			system "rm -f $prevpr_output_file_name";
			system "rm -f ${temp_dir}*.xml";
			system "rm -f ${temp_dir}*.net";
			system "rm -f ${temp_dir}*.place";
			system "rm -f ${temp_dir}*.route";
			system "rm -f ${temp_dir}*.sdf";
			system "rm -f ${temp_dir}*.v";
			if ($do_power) {
				system "rm -f $ace_output_act_path";
			}
		}
	}
	else {
		print("failed: vpr");
		$error_code = 1;
	}
}

my $EndTime = time;

# Determine running time
my $seconds    = ( $EndTime - $StartTime );
my $runseconds = $seconds % 60;

# Start collecting results to output.txt
open( RESULTS, "> $results_path" );

# Output vpr status and runtime
print RESULTS "vpr_status=$q\n";
print RESULTS "vpr_seconds=$seconds\n";

# Parse VPR output
if ( open( VPROUT, "< vpr.out" ) ) {
	undef $/;
	my $content = <VPROUT>;
	close(VPROUT);
	$/ = "\n";    # Restore for normal behaviour later in script

	if ( $content =~ m/(.*Error.*)/i ) {
		$error = $1;
	}
}
print RESULTS "error=$error\n";

close(RESULTS);

# Clean up files not used that take up a lot of space

#system "rm -f *.blif";
#system "rm -f *.xml";
#system "rm -f core.*";
#system "rm -f gc.txt";

#################################################################################
################################## BITSTREAM ####################################
#################################################################################

if ($ending_stage >= $stage_idx_bitstream and ! $error_code)
{
	(my $pkg_file_path = File::Spec->rel2abs($architecture_file_path_orig)) =~ s{(_[^_/]+)?\.[^.]+$}{.pkg};
	(-e "$pkg_file_path") or die("$pkg_file_path does not exist!");
	unless (-e "$temp_dir/".basename($pkg_file_path)) {
		symlink($pkg_file_path, "$temp_dir/".basename($pkg_file_path)) or die;
	}

	(my $tws_file_path = File::Spec->rel2abs($architecture_file_path_orig)) =~ s{\.[^.]+$}{.tws};
	(-e "$tws_file_path") or die("$tws_file_path does not exist!");
	unless(-e "$temp_dir/".basename($tws_file_path)) {
		symlink($tws_file_path, "$temp_dir/".basename($tws_file_path)) or die;
	}

	my @bitgen_options;
	if ($arch eq "xc6vlx240tff1156") {
		unless (-e "$temp_dir/xc6vlx240t.db") {
			symlink("$vtr_flow_path/arch/xilinx/xc6vlx240t.db", "$temp_dir/xc6vlx240t.db") or die;
		}
		unless (-e "$temp_dir/Virtex6.db") {
			symlink("$vtr_flow_path/arch/xilinx/Virtex6.db", "$temp_dir/Virtex6.db") or die;
		}
		unless (-e "$temp_dir/xc6vlx240tff1156_include.xdl") {
			symlink("$vtr_flow_path/arch/xilinx/xc6vlx240tff1156_include.xdl", "$temp_dir/xc6vlx240tff1156_include.xdl") or die;
		}
	}
	else {
		die($arch);
	}

	(-e "$prevpr_output_file_path") or die("$prevpr_output_file_path does not exist!");
	(-e "$temp_dir$benchmark_name.net") or die("$temp_dir$benchmark_name.net does not exist!");
	(-e "$temp_dir$benchmark_name.place") or die("$temp_dir$benchmark_name.place does not exist!");
	(-e "$temp_dir$benchmark_name.route") or die("$temp_dir$benchmark_name.route does not exist!");

	unlink "$temp_dir$benchmark_name".".xdl"; 
	$q = &system_with_timeout($bitstream_path, 
					"bitstream.out",
					$timeout,
					$temp_dir,
					$arch,
					$benchmark_name
	);
	(-e "$temp_dir$benchmark_name".".xdl") or die("$temp_dir$benchmark_name".".xdl does not exist!");

	unlink "$temp_dir$benchmark_name".".ncd"; 
	$q = &system_with_timeout(	
			$xdl_path, 
			"xdl2ncd.out",
			$timeout,
			$temp_dir,
			"-force",
			"-xdl2ncd",
			"$benchmark_name".".xdl",
			"$benchmark_name".".ncd"
	);
	
	(-e "$temp_dir$benchmark_name".".ncd") or die("$temp_dir$benchmark_name".".ncd does not exist!");

	$q = &system_with_timeout(
			$trce_path, 
			"trce.out",
			$timeout,
			$temp_dir,
			"-v", "10",
			"-a",
			"$benchmark_name.ncd"
			);

	unlink "$temp_dir$benchmark_name.bit"; 
	unlink "$temp_dir$benchmark_name.drc"; 
	$q = &system_with_timeout(
			$bitgen_path, 
			"bitgen.out",
			$timeout,
			$temp_dir,
			"-d",
			@bitgen_options,
			"-w", "$benchmark_name.ncd",
			);

	(-e "$temp_dir$benchmark_name.bit") or die("$temp_dir$benchmark_name.ncd does not exist!");
}

if ( !$error_code ) {
	#system "rm -f *.echo";
	print "OK";
}
print "\n";

################################################################################
# Subroutine to execute a system call with a timeout
# system_with_timeout(<program>, <stdout file>, <timeout>, <dir>, <arg1>, <arg2>, etc)
#    make sure args is an array
# Returns: "timeout", "exited", "success", "crashed"
################################################################################
sub system_with_timeout {

	# Check args
	( $#_ > 2 )   or die "system_with_timeout: not enough args\n";
	( -f $_[0] )  or die "system_with_timeout: can't find executable $_[0]\n";
	( $_[2] > 0 ) or die "system_with_timeout: invalid timeout\n";

	# Save the pid of child process
	my $pid = fork;

	if ( $pid == 0 ) {

		# Redirect STDOUT for vpr
		chdir $_[3];

		
		open( STDOUT, "| tee $_[1]" );
		open( STDERR, ">&STDOUT" );
		

		# Copy the args and cut out first four
		my @VPRARGS = @_;
		shift @VPRARGS;
		shift @VPRARGS;
		shift @VPRARGS;
		shift @VPRARGS;

		# Run command
		# This must be an exec call and there most be no special shell characters
		# like redirects so that perl will use execvp and $pid will actually be
		# that of vpr so we can kill it later.
		print "\n$_[0] @VPRARGS\n";
		exec "/usr/bin/time", "-v", $_[0], @VPRARGS;
	}
	else {
		my $timed_out = "false";

		# Register signal handler, to kill child process (SIGABRT)
		$SIG{ALRM} = sub { kill 6, $pid; $timed_out = "true"; };

		# Register handlers to take down child if we are killed (SIGHUP)
		$SIG{INTR} = sub { print "SIGINTR\n"; kill 1, $pid; exit; };
		$SIG{HUP}  = sub { print "SIGHUP\n";  kill 1, $pid; exit; };

		# Set SIGALRM timeout
		alarm $_[2];

		# Wait for child process to end OR timeout to expire
		wait;

		# Unset the alarm in case we didn't timeout
		alarm 0;

		# Check if timed out or not
		if ( $timed_out eq "true" ) {
			return "timeout";
		}
		else {
			my $did_crash = "false";
			if ( $? & 127 ) { $did_crash = "true"; }

			my $return_code = $? >> 8;

			if ( $did_crash eq "true" ) {
				return "crashed";
			}
			elsif ( $return_code != 0 ) {
				return "exited";
			}
			else {
				return "success";
			}
		}
	}
}

sub stage_index {
	my $stage_name = $_[0];

	if ( lc($stage_name) eq "odin" ) {
		return $stage_idx_odin;
	}
	if ( lc($stage_name) eq "abc" ) {
		return $stage_idx_abc;
	}
	if ( lc($stage_name) eq "ace" ) {
		return $stage_idx_ace;
	}
	if ( lc($stage_name) eq "prevpr" ) {
		return $stage_idx_prevpr;
	}
	if ( lc($stage_name) eq "vpr" ) {
		return $stage_idx_vpr;
	}
	if ( lc($stage_name) eq "bitstream" ) {
		return $stage_idx_bitstream;
	}
	return -1;
}

sub file_ext_for_stage {
	my $stage_idx = $_[0];

	if ( $stage_idx == 0 ) {
		return ".v";
	}
	elsif ( $stage_idx == $stage_idx_odin ) {
		return ".odin.blif";
	}
	elsif ( $stage_idx == $stage_idx_abc ) {
		return ".abc.blif";
	}
	elsif ( $stage_idx == $stage_idx_ace ) {
		return ".ace.blif";
	}
	elsif ( $stage_idx == $stage_idx_prevpr ) {
		return ".pre-vpr.blif";
	}
}

sub expand_user_path {
	my $str = shift;
	$str =~ s/^~\//$ENV{"HOME"}\//;
	return $str;
}

sub file_find_and_replace {
	my $file_path      = shift();
	my $search_string  = shift();
	my $replace_string = shift();

	open( FILE_IN, "$file_path" );
	my $file_contents = do { local $/; <FILE_IN> };
	close(FILE_IN);

	$file_contents =~ s/$search_string/$replace_string/mg;

	open( FILE_OUT, ">$file_path" );
	print FILE_OUT $file_contents;
	close(FILE_OUT);
}

sub xml_find_key {
	my $tree = shift();
	my $key  = shift();

	foreach my $subtree ( keys %{$tree} ) {
		if ( $subtree eq $key ) {
			return $tree->{$subtree};
		}
	}
	return "";
}

sub xml_find_child_by_key_value {
	my $tree = shift();
	my $key  = shift();
	my $val  = shift();

	if ( ref($tree) eq "HASH" ) {

		# Only a single item in the child array
		if ( $tree->{$key} eq $val ) {
			return $tree;
		}
	}
	elsif ( ref($tree) eq "ARRAY" ) {

		# Child Array
		foreach my $child (@$tree) {
			if ( $child->{$key} eq $val ) {
				return $child;
			}
		}
	}

	return "";
}

sub xml_find_LUT_Kvalue {
	my $tree = shift();

	#Check if this is a LUT
	if ( xml_find_key( $tree, "-blif_model" ) eq ".names" ) {
		return $tree->{input}->{"-num_pins"};
	}

	my $max = 0;
	my $val = 0;

	foreach my $subtree ( keys %{$tree} ) {
		my $child = $tree->{$subtree};

		if ( ref($child) eq "ARRAY" ) {
			foreach my $item (@$child) {
				$val = xml_find_LUT_Kvalue($item);
				if ( $val > $max ) {
					$max = $val;
				}
			}
		}
		elsif ( ref($child) eq "HASH" ) {
			$val = xml_find_LUT_Kvalue($child);
			if ( $val > $max ) {
				$max = $val;
			}
		}
		else {

			# Leaf - do nothing
		}
	}

	return $max;
}

sub xml_find_mem_size_recursive {
	my $tree = shift();

	#Check if this is a Memory
	if ( xml_find_key( $tree, "-blif_model" ) =~ "port_ram" ) {
		my $input_pins = $tree->{input};
		foreach my $input_pin (@$input_pins) {
			if ( xml_find_key( $input_pin, "-name" ) =~ "addr" ) {
				return $input_pin->{"-num_pins"};
			}
		}
		return 0;
	}

	# Otherwise iterate down
	my $max = 0;
	my $val = 0;

	foreach my $subtree ( keys %{$tree} ) {
		my $child = $tree->{$subtree};

		if ( ref($child) eq "ARRAY" ) {
			foreach my $item (@$child) {
				$val = xml_find_mem_size_recursive($item);
				if ( $val > $max ) {
					$max = $val;
				}
			}
		}
		elsif ( ref($child) eq "HASH" ) {
			$val = xml_find_mem_size_recursive($child);
			if ( $val > $max ) {
				$max = $val;
			}
		}
		else {

			# Leaf - do nothing
		}
	}

	return $max;
}

sub xml_find_mem_size {
	my $tree = shift();

	my $pb_tree = $tree->{architecture}->{complexblocklist}->{pb_type};
	if ( $pb_tree eq "" ) {
		return "";
	}

	my $memory_pb = xml_find_child_by_key_value ($pb_tree, "-name", "RAMB36E1");
	if ( $memory_pb eq "" ) {
		return "";
	}

	return xml_find_mem_size_recursive($memory_pb);
}
