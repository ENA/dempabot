use List::Util 'shuffle';
use IO::File;

use Encode;

#グローバル
my $NOISE_FILE = 'noise.txt';

#mainルーチン
sub main{
	#コマンドライン引数を受け取ります
	if (@ARGV < 0) {
		print "usage: none\n";
		exit(0);
	}
	
	#ノイズファイルを開きます	
	open(NIS,$NOISE_FILE);
	my @noise = <NIS>;
	chomp(@noise);
	close(NIS);
	
	my $outtext='';
	
	foreach my $line(@noise){
		$outtext .= $line;
	}
	$outtext =~ s/ //g;
	$outtext =~ s/\t//g;

	$outtext = Encode::decode_utf8($outtext);		

	my @randout = ();
	while(1){
		my $text;
		$text = substr($outtext,0,1,"");		
		if($text eq ""){ last; }
		push(@randout,$text);
	}
	@randout = List::Util::shuffle(@randout);
	
	$outtext = join("",@randout);
	
	open(NISO,"> $NOISE_FILE");

	my $text = "";
	while(1){
			
		$text = substr($outtext,0,80,"");
		$text = Encode::encode_utf8($text);		
		
		if($text eq ""){ last; }
		
		print NISO $text;
		if(substr($outtext,0,80) ne "") { print NISO "\n"; }
	}
	
	close(NISO);

	return 0;

}
#mainルーチン終わり


#メインからプログラム開始
exit( main::main() );