#Dempabot
#You need some module for expamle "XML::Simple" "Data::Dumper" "LWP::UserAgent" "MeCab" and so on.

use strict;
use warnings;
use Encode;

#import some modules
use LWP::UserAgent;
use IO::File;
use XML::Simple;
use Data::Dumper;

#言語判定モジュール。
use Lingua::LanguageGuesser;
#twitterの検索結果はatomでしか受け取れないので、それのモジュール。
use XML::FeedPP;
#MeCab
use MeCab;

#ソースコードはUTF-8で記述される。
use utf8;
#基本的な入出力は全てUTF8だが、STDINとSTDOUT,STDERRのみは全てShiftJISとする。(設定は下の変数いじれば換えられる。)
my $CPSTDIN = 'shiftjis';
my $CPSTDOUT = 'shiftjis';
my $CPSTDERR = 'shiftjis';
use open ":utf8";

#XML::Simpleのおまじない
$XML::Simple::PREFERRED_PARSER = 'XML::Parser';

#Twitter Oauth
use Net::Twitter::Lite;


#ファイル名をあらわすグローバル変数
my $NOISE_FILE = '../etc/noise.txt';
my $PASSWORD_FILE = '../etc/passwd.csv';
my $MRCV_FILE = '../etc/mrcv.txt';
my $RAND_FILE = '../etc/rand.txt';
my $LOCALREAD_FILE = 'localread.txt';
my $LOCALMRCV_FILE = 'localmrcv.txt';
my $FOLLOWLIST_FILE = '../etc/followlist.txt';
my $HTTPLOG_FILE = '../var/access.log';


#2分探索でファイルの配列から色々探します
#最初の二つが見つかれば1を返し、そのインデックスを返す。
#見つからなければ、それぞれの境目を$maxと$minに見つけ出して返す。
sub findHeadWord
{
	my($refmrc,$searchword1,$searchword2) = @_;
	
    #一番最初。
	my $max = @$refmrc-1;
	my $min = 0;
	my $nowindex = int(($max+$min) / 2);
	
	my $flag_last = 0;  #次回終了フラグ
    
	while(1){			
					
		if($max == -1) { return (0,$nowindex,$max,$min); }
		if($max == 0 ) { $flag_last = 1;}
					
		#頭のパターンが一致した場合は１
		if( ($refmrc->[$nowindex][1] eq $searchword1) &&
		    ($refmrc->[$nowindex][2] eq $searchword2) ){
			
			return (1,$nowindex,$max,$min);
		}
		
		#見つかりませんでした。帰るのは0。
		if($flag_last == 1){
			
			return (0,$nowindex,$max,$min);
		}
		
		#見つからないときに調べること、文字列
		if   ($searchword1 gt $refmrc->[$nowindex][1]){
			$min = $nowindex;
		}
		elsif($searchword1 lt $refmrc->[$nowindex][1]){
			$max = $nowindex;
		}
		elsif($searchword2 gt $refmrc->[$nowindex][2]){
			$min = $nowindex;
		}
		elsif($searchword2 lt $refmrc->[$nowindex][2]){
			$max = $nowindex;
		}
		else{
			print STDERR "333\n";
			exit(-1);
		}
		
		#移動量減少。ただし０にはしない。その次で最後の探索とする。
		if($nowindex == int( ($max+$min) / 2 ) ){
			$flag_last = 1;
			if($max == $nowindex){$nowindex = $min;}
			elsif($min == $nowindex){$nowindex = $max;}
			else{
				print STDERR "111\n";
				exit(-1);
			}
		}
		else{
			$nowindex = int( ($max+$min) / 2) ;
    	}				
	}
	
}


#ランダムに定型文を返します
sub genRandComment{
	my($randfile) = @_;
	
	open(RND,"$randfile") or die "$randfile CAN'T OPEN!!!\n";		
	my @comment = <RND>;
	chomp(@comment);
	close(RND);
	return $comment[int(rand(@comment))];
	
}

#マルコフを開いて配列に突っ込みます
sub openMrcvFile{
	my ($mrcname,$refmrc,$refheads) = @_;
	
	open(RMRC,"$mrcname") or die "$mrcname CAN'T OPEN!!!\n";
	
	my $i=0;
	foreach my $rawline(<RMRC>){
		chomp($rawline);
		my @words = split(/<!>/,$rawline);
		push(@$refmrc,[@words]);
		
		#ついでに適当に頭を探します
		if($words[0] eq 'STRT') { push(@$refheads,$i); }
		
		$i++;
	}
	
	close(RMRC);
	
	return 0;
}

#配列の内容を書き込みます
sub writeMrcvFile{
	my ($mrcname,$refmrc) = @_;
	#write
	open(WMRC,">$mrcname");
	for(my $j=0;$j<@$refmrc;$j++){
	
		my $writeline;
	
		for(my $i=0;$i<@{$refmrc->[$j]};$i++){
			if($i==0){ $writeline = $refmrc->[$j][0]; }
			else{ $writeline .= '<!>'.$refmrc->[$j][$i]; }
		}
		$writeline .= "\n";
		print WMRC $writeline;
	}
	close(WMRC);
	
	return 0;
}

#マルコフの結ワードを検索
sub findLastWord{
	my($refmrcline,$lastword) = @_;
	
	my $i=3;
	for($i=3;$i<@{$refmrcline};$i++){
		if($lastword eq $refmrcline->[$i]){
			return (1,$i);
		}
	}
	return (0,$i);
}

#まるこふをフル活用します
sub genMrcvComment{
	my ($mrcname) = @_;
	my @mrcfile=();
	my @heads=();

	openMrcvFile($mrcname,\@mrcfile,\@heads);
		
	#文頭
	my $head;
	
	#もし@始まりを選んだ場合、やり直す。
	do{
		#頭を取ってきます
		$head = $heads[int(rand(@heads))];
	}while($mrcfile[$head][1] eq '@');
	
    #今の読み出し位置
	my $nowread = $head;
	
	#頭から適当に探って文を作ります
	my $genstr = "";
	$genstr .= $mrcfile[$nowread][1].$mrcfile[$nowread][2]; 
	while(1){
		#最後尾を見つけたらそこで終わり
		#my @lfindres = findLastWord($mrcfile[$nowread],'<。。。>');
		#if($lfindres[0]==1){last;}
		
		#適当に最後尾をランダムで選び、文に加える。
		my $lselect = int(rand(@{$mrcfile[$nowread]}-3))+3;
		#最後尾なら終わる
		if($mrcfile[$nowread][$lselect] eq '<。。。>'){last;}
		$genstr .= $mrcfile[$nowread][$lselect];
		
		#それに続く文脈を探して、nowreadを書き換える。見つからないことはありえない。
		my @afindres = findHeadWord(\@mrcfile,$mrcfile[$nowread][2],$mrcfile[$nowread][$lselect]);
		if($afindres[0]==0){ print STDERR "666\n"; }
		$nowread = $afindres[1];
	}
	
	return $genstr;	
}

#ノイズファイルの配列を貰う
sub getNoise
{
	my($noisefile,$refnoise) = @_;
	
	#ノイズファイルを開きます
	open(NIS,$noisefile) or die "$noisefile CAN'T OPEN!!!\n";
	@$refnoise = <NIS>;
	chomp(@$refnoise);
	close(NIS);

	return 0;
}

#ノイズを生成します
sub genNormalizeNoise
{
	my($refnoise,$max,$min) = @_;
		
	my $randstr = $refnoise->[int(rand(@$refnoise))];
	my $randlen = int(rand($max-$min+1)) + $min;

	my $randpos = int(rand(length($randstr)));
	if(length($randstr)-$randpos < $randlen){ $randpos = length($randstr)-$randlen; }
	
	#print $randpos.':'.$randlen."\n";
	
	$randstr = substr($randstr,$randpos,$randlen);
	$randstr =~ s/[\r\n]//g;
	
	return $randstr;
}

#ぶつ切り配列変換
sub TransToSplitArray{
	my ($plane) = @_;

	#文字コード
	my $mecab = new MeCab::Tagger("");
	my $mecabDicInfo = $mecab->dictionary_info();
	my $charset = $mecabDicInfo->swig_charset_get();
	
	#encodeしたものをわたすこと
	my $node = $mecab->parseToNode(Encode::encode($charset,$plane));
	
	#ぶつ切り文章作成
	my @wordlist = ();
	while($node = $node->{next}){
	
		#encodeされているのでdecodeする。
		my $read = $node->{surface};
		Encode::from_to($read,$charset,'utf8');
		$read = Encode::decode('utf8',$read);
		
		#つなぐ
	    push(@wordlist,$read);
	}
	pop(@wordlist); #ケツにいらないのがあるので消す

	return @wordlist;
}


#適当にノイズを混ぜます
sub addNoise
{
	my ($planetxt,$max,$min) = @_;
	my @splt = TransToSplitArray($planetxt);

	my $refnoise = [()];
	getNoise($NOISE_FILE,$refnoise);
	my $wet = genNormalizeNoise($refnoise,$max,$min);

	foreach my $val(@splt){
		$wet .= $val;
		$wet .= genNormalizeNoise($refnoise,$max,$min);
	}
	
	return $wet;
}

#ボットコメント生成
sub genBotComment
{
	my($mrcvname) = @_;

	#ランダム値
	my $selectbase = int(rand(10000));
	#ノイズ度
	my $maxnoiselength = 0;
	my $minnoiselength = 0;
	#ジェネレータ選択
	my $genSystem = 0;
	#特殊付加文および装飾
	my $decorate = 0x00;

	#10.00%の確率でノイズのみ
	if   ($selectbase < 1000){
		$maxnoiselength = 70;
		$minnoiselength = 45;
		$genSystem = 0;
	}
	#65.00%の確率でノイズ付きのマルコフ文
	elsif($selectbase < 7500){
		$maxnoiselength = 4;
		$minnoiselength = 0;
		$genSystem = 1;
		$decorate |= 0x01;
	}
	#15.00%の確率でノイズの無いマルコフ文
	elsif($selectbase < 9000){
		$maxnoiselength = 0;
		$minnoiselength = 0;
		$genSystem = 1;
	}
	#7.00%の確率でノイズ付の定型文
	elsif($selectbase < 9700){
		$maxnoiselength = 2;
		$minnoiselength = 0;
		$genSystem = 2;
	}
	#3.00%の確率でノイズの無い定型文
	else{
		$maxnoiselength = 0;
		$minnoiselength = 0;
		$genSystem = 2;
	}
		
	#動作実行
	my $gentext = '';
	#生成エンジン
	if   ($genSystem == 1){ $gentext = genMrcvComment($mrcvname); }
	elsif($genSystem == 2){ $gentext = genRandComment($RAND_FILE); }
	#ノイズ付加
	$gentext = addNoise($gentext,$maxnoiselength,$minnoiselength);
	
	#カッコ付け
	if   ($decorate & 0x01){
		$gentext = '『'.$gentext.'』';
	}
	
	#文字の長さを160文字に切る
	$gentext = substr($gentext,0,160);

	#生成した文章を返す	
	return $gentext;
}


#マルコフを更新する
sub RefleshMarcov{
	my ($mrcname,$stout,@plane_array) = @_;
	
	my @mrcfile = ();
	my @heads = ();
	
	#MRCVを開く
	openMrcvFile($mrcname,\@mrcfile,\@heads);
	
	#表示
	if($stout == "1"){ print STDOUT "RefleshMRCV please wait...\n"; }
	
	#配列ごとに
	foreach my $plane(@plane_array){
	
		#ぶつ切り文字列へ変換
		my @wordlist = TransToSplitArray($plane);
		
		#表示
		if($stout == "1"){
			foreach my $val(@wordlist){
				print STDOUT Encode::encode($CPSTDOUT,$val)." <> ";
			}
			print STDOUT "\n";
		}

		
			
		#文字数があれならはじく
		if(@wordlist < 2){ next; }
		
		for(my $i=0;$i<@wordlist;$i++){
			#特殊文字対策
			$wordlist[$i] =~ s/<!>/\&lt;!\&gt;/g;
			
			#改行対策
			$wordlist[$i] =~ s/\r//g;
			$wordlist[$i] =~ s/\n/<。。。>/g;
			
			#「。」の次には必ず<。。。>を挿入する。
			if($wordlist[$i] eq '。'){
				splice(@wordlist,$i+1,0,('<。。。>'));
	    	}
		}    	
		
		#@wordlistの末尾に<。。。>をいれて文末としておきます。
		push(@wordlist,'<。。。>');
    	
		#確認していきます
		for(my $i=0;$i<@wordlist-2;$i++){
    	    				
			#文の終わりが頭にある場合には無視する。
			if( ($wordlist[$i+0] eq '<。。。>') || ($wordlist[$i+1] eq '<。。。>') ){ next; }

			#検索します
			my @resseekh = findHeadWord(\@mrcfile,$wordlist[$i+0],$wordlist[$i+1]);
			#先頭二つが見つかった場合
			if($resseekh[0]==1){
				#三つ目を探す
       			my @resseekl = findLastWord($mrcfile[$resseekh[1]],$wordlist[$i+2]);
				#三つ目が見つからなかった場合、そこに追加する。
				if($resseekl[0]==0){
					#三つ目のところに追加
					$mrcfile[$resseekh[1]][$resseekl[1]] = $wordlist[$i+2];
					#もしそれが文頭だった場合、フラグを変更する。
					if($i==0 || $wordlist[$i-1] eq '<。。。>'){$mrcfile[$resseekh[1]][0]="STRT";}
				}
			}
			#先頭二つが見つからなかった場合の追加処理は前のとおり。
			else{
				my $flag="NONE";
				my $max = $resseekh[2];
				my $min = $resseekh[3];
				
				#もし、文頭である場合、フラグを立てる。
				if($i==0 || $wordlist[$i-1] eq '<。。。>'){$flag = "STRT";}
				
				#文字列を挿入する位置を指定する
				my $insertpos=-1;			
				
				#maxが0の場合、中身が全く無いため、0に挿入する。
				if($max == -1){ $insertpos = 0; }
				#maxより大きい
				elsif($wordlist[$i+0] gt $mrcfile[$max][1]){ $insertpos = $max+1; }
				#minより小さい
				elsif($wordlist[$i+0] lt $mrcfile[$min][1]){ $insertpos = $min; }
				#maxと同じで2がmaxより大きい
				elsif($wordlist[$i+0] eq $mrcfile[$max][1] && $wordlist[$i+1] gt $mrcfile[$max][2]){ $insertpos = $max+1; }
				#minと同じで2がminより小さい
 				elsif($wordlist[$i+0] eq $mrcfile[$min][1] && $wordlist[$i+1] lt $mrcfile[$min][2]){ $insertpos = $min; }
				#maxとminが一つ目で異なる=真ん中にいれればいい
				elsif($mrcfile[$max][1] ne $mrcfile[$min][1]){ $insertpos = $max; }
				#一つ目で同じだが、二つ目で異なる=真ん中に入れればいい
				elsif($mrcfile[$max][2] ne $mrcfile[$min][2]){ $insertpos = $max; }
				#1と2が同じ、というのはありえない。
				else{
					print STDERR "222\n";
					exit(-1);
				}
				#真ん中のポジション0以下とかありえないです
				if($insertpos < 0){
					print STDERR "444\n";
					exit(-1);
				}
				#指定どおりに追加
				splice(@mrcfile,$insertpos,0,([($flag,$wordlist[$i+0],$wordlist[$i+1],$wordlist[$i+2])]));			
			}    	
		}	
	
	}

	if($stout == "1"){ print STDOUT "...Done.\nWrite to MRC_FILE. please wait...\n"; }
		
	writeMrcvFile($mrcname,\@mrcfile);
	
	if($stout == "1"){ print STDOUT "...Done.\n"; }
	
	return();
}

#引数を指定して適当に情報を受け取ります
sub connectbyHTTP
{
	my($url,$method,$filename) = @_;
		
	# ユーザ・エージェント　オブジェクトを作成します
	my $ua = LWP::UserAgent->new;
	$ua->agent('Dempabot v(1.0) d(2009/09/30)');
	
	# リクエストを作成します
	my $req = HTTP::Request -> new($method => $url);
	
	# ユーザ・エージェントにリクエストを渡し、返されたレスポンスを取得します
	my $res;
	
	#ファイル名があればそれを指定する
	if($filename ne '')
	{
		$res = $ua->request($req,$filename);
	}
	else{
		$res = $ua->request($req);
	}

	#現在の時間を取得します
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
	my @weekday = qw(Sun Mon Tue Wed Thu Fri Sat);
	my @month = qw(Jan Feb Mar Apl May Jun Jul Aug Sep Oct Nov Dec);
	$year += 1900;
	my $log = $year.'/'.$month[$mon].'/'.$mday.'('.$weekday[$wday].')'.$hour.':'.$min.':'.$sec."\tHTTP:".$res->code."\t".$url."\n";
		
	#ログファイルを保存します
	open(LOG,">> $HTTPLOG_FILE");
	print LOG $log;
	close(LOG);
	
	# レスポンスの結果をチェックします
	if ($res->is_error()) {
	     print "Bad luck this time\n";
	     print Encode::encode($CPSTDOUT,$url)."\n";
	     die Encode::encode($CPSTDOUT,$!);
	}
	
	#返します
	return $res;
}

#フォローリスト
sub forwardFollowList
{
	my($filename,$times) = @_;

	my $ret = '';

	#読む
	open(FLF,$filename);
	my @flf = <FLF>;
	chomp(@flf);
	close(FLF);
		
	#更新
	for(my $i=0;$i<$times;$i++){
		$ret = shift(@flf);
		push(@flf,$ret);
	}
	
	#書く
	open(FLF,"> $filename");
	foreach my $wfl(@flf){
		print FLF $wfl."\n";
	}
	close(FLF);
	
	return $ret;
}


#mainルーチン
sub main{
	#とりあえず乱数の種を生成しておきます
	srand(time^($$+($$ << 15)));

	#コマンドライン引数を受け取ります
	if (@ARGV < 1) {
		print "usage: command\n";
		exit(0);
	}
	
	#パスワードファイルを読む	
	open(PSW,$PASSWORD_FILE);
	my @userdata = split(",",<PSW>);
	close(PSW);
	chomp @userdata;
	my ($CONSUMER_KEY,$CONSUMER_SECRET,$ACCESS_TOKEN,$ACCESS_TOKEN_SECRET) = @userdata;
	
	
	#OAuth準備
	my $oauthobj = Net::Twitter::Lite->new(
		traits => [qw/API::REST OAuth WrapError/],
		consumer_key => $CONSUMER_KEY,
		consumer_secret => $CONSUMER_SECRET,
		ssl => 1
	);

	$oauthobj->access_token($ACCESS_TOKEN);
	$oauthobj->access_token_secret($ACCESS_TOKEN_SECRET);

	
	#コマンドごとの処理
	my $command = $ARGV[0];
	if($command eq "test"){
		my $status = $oauthobj->update({ status => 'Perlで投稿テスト'.time() });
		print Dumper $status;
	}

	elsif($command eq "read"){
		my @addtext = ();
		my $array_ref = $oauthobj->friends_timeline({count => '200'});
		foreach my $hash_ref(@$array_ref){ push(@addtext,$hash_ref->{'text'}); }
		RefleshMarcov($MRCV_FILE,0,@addtext);
		
	}
	
	#通常投稿
	elsif($command eq "post")
	{
		$oauthobj->update({ status => genBotComment($MRCV_FILE) });
	}
	
	#ローカルで文章ファイルを読み取りますが、MRCVは別に出力します。
	elsif($command eq "read_local"){
		open(PLN,$LOCALREAD_FILE);
		my @init = <PLN>;
		RefleshMarcov($LOCALMRCV_FILE,1,@init);
		close(PLN);
	}

	#ローカルで文章ファイルを読み取り,本物のMRCVを更新します。
	elsif($command eq "read_bylocal"){
		open(PLN,$LOCALREAD_FILE);
		my @init = <PLN>;
		RefleshMarcov($MRCV_FILE,0,@init);
		close(PLN);
	}
	#本番どおりの設定を使いつつ、生成した文章をローカルに出力します。
	elsif($command eq "post_tolocal"){
		my $t = genBotComment($MRCV_FILE);

		print STDOUT Encode::encode($CPSTDOUT,$t)."\n";
	}

	#別のマルコフファイルを使い、ローカルで文章を生成します
	elsif($command eq "post_local"){
		my $t = genBotComment($LOCALMRCV_FILE);

		print STDOUT Encode::encode($CPSTDOUT,$t)."\n";
	}
	
	#返答を読みます
	elsif($command eq "read_rep")
	{
		my @addtext = ();
		my $array_ref = $oauthobj->mentions({count => '200'});
		foreach my $hash_ref(@$array_ref){ push(@addtext,$hash_ref->{'text'}); }
		RefleshMarcov($MRCV_FILE,1,@addtext);
	}
	
	#フォローリストに従い、一番上のユーザーの発言を読みこみ、リストの一番下に回します。
	elsif($command eq "read_byfollowlist"){
		my @addtext = ();
		my $readuser = forwardFollowList($FOLLOWLIST_FILE,1);
		my $array_ref = $oauthobj->user_timeline({id => $readuser , count => '200'});
		foreach my $hash_ref(@$array_ref){ push(@addtext,$hash_ref->{'text'}); }
		RefleshMarcov($MRCV_FILE,0,@addtext);
	}
	
	#コマンドが無いよ
	else{
		print 'You executed the command "'.Encode::encode($CPSTDOUT,$command).'" but it isn\'t supported.';
	}
	
	return 0;

}
#mainルーチン終わり


#メインからプログラム開始
exit( main::main() );
