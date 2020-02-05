#!/bin/sh
# human single DRA001287 => DRP001358
# mouse paired GSE90487 => SRP093881
# mouse single E-MTAB-3543 =>
# human single PRJEB8994 =>
# umap clustering
# gene coverage
# kraken crona
# expression table TPM
mkdir -p data
mkdir -p data/rDNA
mkdir -p data/genome
mkdir -p data/STAR
mkdir -p data/runinfo
mkdir -p data/fastq
mkdir -p data/filtered
mkdir -p data/bam
mkdir -p data/unmap

perl rdf.pl -d singlecell.sqlite3 -q rmexec
if [ "$1" == "submit" ] ; then
  perl rdf.pl -d singlecell.sqlite3 input singlecell '#userid'
elif [ "$1" == "setup" ] ; then
  perl rdf.pl -d singlecell.sqlite3 prompt 'Homo sapiens' '#rDNA' "Path to Homo sapiens rDNA [default is download] ? "
  perl rdf.pl -d singlecell.sqlite3 prompt hg38 '#genome' "Path to Homo sapiens genome [default is download] ? "
  perl rdf.pl -d singlecell.sqlite3 prompt 'Mus musculus' '#rDNA' "Path to Mus musculus rDNA [default is download] ? "
  perl rdf.pl -d singlecell.sqlite3 prompt mm10 '#genome' "Path to Mus musculus genome [default is download] ? "
  perl rdf.pl -d singlecell.sqlite3 insert singlecell '#species' 'Homo sapiens'
  perl rdf.pl -d singlecell.sqlite3 insert singlecell '#species' 'Mus musculus'
  perl rdf.pl -d singlecell.sqlite3 insert 'Homo sapiens' '#assembly' 'hg38'
  perl rdf.pl -d singlecell.sqlite3 insert 'Mus musculus' '#assembly' 'mm10'

  echo "#0 Installing softwares"
  perl rdf.pl -d singlecell.sqlite3 install tagdust STAR samtools bedtools

  echo "#1 Downloading ribosomalDNA"
  perl moirai2.pl -m 10 \
  -d singlecell.sqlite3 \
  -i '$singlecell->#species->Homo sapiens' \
  -o 'Homo sapiens->#rDNA->$output' \
  https://github.com/moirai2/moirai2.github.io/database/ncbi/rDNA/Homo_sapiens_rDNA.json \
  '$output=data/rDNA/human_rDNA.fa'

  perl moirai2.pl -m 10 \
  -d singlecell.sqlite3 \
  -i '$singlecell->#species->Mus musculus' \
  -o 'Mus musculus->#rDNA->$output' \
  https://github.com/moirai2/moirai2.github.io/database/ncbi/rDNA/Mus_musculus_rDNA.json \
  '$output=data/rDNA/mouse_rDNA.fa'

  echo "#2 Downloading genomes"
  perl moirai2.pl -m 1 \
  -d singlecell.sqlite3 \
  -i 'Homo sapiens->#assembly->$assembly' \
  -o '$assembly->#genome->$path' \
  https://github.com/moirai2/moirai2.github.io/database/genome/Homo_sapiens_hg38_chr22.json \
  '$path=data/genome/$assembly.fa'

  perl moirai2.pl -m 1 \
  -d singlecell.sqlite3 \
  -i 'Mus musculus->#assembly->$assembly' \
  -o '$assembly->#genome->$path' \
  https://github.com/moirai2/moirai2.github.io/database/genome/Mus_musculus_mm10_chr19.json \
  '$path=data/genome/$assembly.fa'

  echo "#3 Indexing genomes"
  perl moirai2.pl -m 1 \
  -d singlecell.sqlite3 \
  -i '$assembly->#genome->$reference' \
  -o '$assembly->#STAR->$outdir' \
  https://github.com/moirai2/moirai2.github.io/command/STAR/index_reference.json \
  '$outdir=data/STAR/$assembly' \
  '$stdout=data/STAR/$assembly/index.stdout' \
  '$stderr=data/STAR/$assembly/index.stderr' \
  '$log=data/STAR/$assembly/index.log'
  exit
fi

echo "#1 converting userdefinedid to studyid"
perl moirai2.pl \
-d singlecell.sqlite3 \
-i 'singlecell->#userid->$userdefinedid' \
-o '$userdefinedid->#studyid->$studyid,singlecell->#studyid->$studyid' \
https://github.com/moirai2/moirai2.github.io/command/edirect/userdefinedid_to_studyid.json

echo "#2 Retrieving runinfo and summary files"
perl moirai2.pl \
-d singlecell.sqlite3 \
-i 'singlecell->#studyid->$studyid' \
-o '$studyid->#runinfo->$runinfo,$studyid->#summaryfile->$summary' \
https://github.com/moirai2/moirai2.github.io/command/edirect/studyid_to_sra_info_files.json \
'$runinfo=data/runinfo/$studyid.runinfo.txt' \
'$summary=data/runinfo/$studyid.summary.txt'

echo "#3 Importing species and runinfo to database"
perl moirai2.pl \
-d singlecell.sqlite3 \
-i '$studyid->#runinfo->$runinfo' \
-o '$studyid->#runinfo_imported->true' \
https://github.com/moirai2/moirai2.github.io/command/edirect/import_runinfo_to_database.json \
'$label=ScientificName,LibraryLayout'

echo "#4 Downloading fastq files"
perl moirai2.pl \
-d singlecell.sqlite3 \
-i '$studyid->#Run->$runid,$runid->#LibraryLayout->PAIRED' \
-o '$runid->#read1->$read1,$runid->#read2->$read2,$runid->#count1->$count1,$runid->#count2->$count2' \
https://github.com/moirai2/moirai2.github.io/command/sratoolkit/fastq_dump_paired.json \
'$read1=data/fastq/$studyid.$runid.read1.fq.gz' \
'$read2=data/fastq/$studyid.$runid.read2.fq.gz'

perl moirai2.pl \
-d singlecell.sqlite3 \
-i '$studyid->#Run->$runid,$runid->#LibraryLayout->SINGLE' \
-o '$runid->#read1->$read1,$runid->#count1->$count1' \
https://github.com/moirai2/moirai2.github.io/command/sratoolkit/fastq_dump_single.json \
'$read1=data/fastq/$studyid.$runid.read1.fq.gz'

echo "#5 Filtering ribosomalRNA"
perl moirai2.pl \
-d singlecell.sqlite3 \
-i '$studyid->#Run->$runid,$runid->#LibraryLayout->SINGLE,$runid->#read1->$input,$runid->#ScientificName->$species,$species->#rDNA->$reference' \
-o '$runid->#tagdustlog->$log,$runid->#filtered1->$filtered,$runid->#artifact1->$artifact' \
https://github.com/moirai2/moirai2.github.io/command/tagdust/tagdust_single.json \
'$log=data/filtered/$studyid.$runid.log' \
'$filtered=data/filtered/$studyid.$runid.filtered.read1.fq.gz' \
'$artifact=data/filtered/$studyid.$runid.artifact.read1.fq.gz'

perl moirai2.pl \
-d singlecell.sqlite3 \
-i '$studyid->#Run->$runid,$runid->#LibraryLayout->PAIRED,$runid->#read1->$input1,$runid->#read2->$input2,$runid->#ScientificName->$species,$species->#rDNA->$reference' \
-o '$runid->#tagdustlog->$log,$runid->#filtered1->$filtered1,$runid->#filtered2->$filtered2,$runid->#artifact1->$artifact1,$runid->#artifact2->$artifact2' \
https://github.com/moirai2/moirai2.github.io/command/tagdust/tagdust_paired.json \
'$log=data/filtered/$studyid.$runid.log' \
'$filtered1=data/filtered/$studyid.$runid.filtered.read1.fq.gz' \
'$filtered2=data/filtered/$studyid.$runid.filtered.read2.fq.gz' \
'$artifact1=data/filtered/$studyid.$runid.artifact.read1.fq.gz' \
'$artifact2=data/filtered/$studyid.$runid.artifact.read2.fq.gz'

echo "#6 Aligning to genome"
perl moirai2.pl \
-d singlecell.sqlite3 \
-i '$studyid->#Run->$runid,$runid->#LibraryLayout->SINGLE,$runid->#filtered1->$input,$runid->#ScientificName->$species,$species->#assembly->$assembly,$assembly->#STAR->$starindex' \
-o '$runid->#bam->$bam,$runid->#bamlog->$log' \
https://github.com/moirai2/moirai2.github.io/command/STAR/align_single.json \
'$bam=data/bam/$studyid.$runid.bam' \
'$log=data/bam/$studyid.$runid.log'

perl moirai2.pl \
-d singlecell.sqlite3 \
-i '$studyid->#Run->$runid,$runid->#LibraryLayout->PAIRED,$runid->#filtered1->$input1,$runid->#filtered2->$input2,$runid->#ScientificName->$species,$species->#assembly->$assembly,$assembly->#STAR->$starindex' \
-o '$runid->#bam->$bam,$runid->#bamlog->$log' \
https://github.com/moirai2/moirai2.github.io/command/STAR/align_paired.json \
'$bam=data/bam/$studyid.$runid.bam' \
'$log=data/bam/$studyid.$runid.log'

echo "#7 Remove multimap from unmap"
perl moirai2.pl \
-d singlecell.sqlite3 \
-i '$studyid->#Run->$runid,$runid->#LibraryLayout->SINGLE,$runid->#bam->$input' \
-o '$runid->#unmap1->$unmap1,$runid->#multicount->$multicount' \
https://github.com/moirai2/moirai2.github.io/command/STAR/remove_multimap_single.json \
'$unmap1=data/unmap/$studyid.$runid.unmap1.fq.gz'

perl moirai2.pl \
-d singlecell.sqlite3 \
-i '$studyid->#Run->$runid,$runid->#LibraryLayout->PAIRED,$runid->#bam->$input' \
-o '$runid->#unmap1->$unmap1,$runid->#unmap2->$unmap2,$runid->#multicount->$multicount' \
https://github.com/moirai2/moirai2.github.io/command/STAR/remove_multimap_paired.json \
'$unmap1=data/unmap/$studyid.$runid.unmap1.fq.gz' \
'$unmap2=data/unmap/$studyid.$runid.unmap2.fq.gz'

echo "#8 Filter artifacts from unmap"
