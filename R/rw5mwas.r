qqPlotFast = function(pvalues, ntests=NULL, ci.level=0.05){
	
	if(is.null(ntests))
		ntests = length(pvalues);
	
	if(is.unsorted(pvalues))
		pvalues = sort.int(pvalues);
	
	ypvs = -log10(pvalues);
	xpvs = -log10(seq_along(ypvs) / ntests);
	
	if(length(ypvs) > 1000) {
		# need to filter a bit, make the plotting faster
		levels = as.integer( (xpvs - xpvs[1])/(tail(xpvs,1) - xpvs[1]) * 2000);
		keep = c(TRUE, diff(levels)!=0);
		levels = as.integer( (ypvs - ypvs[1])/(tail(ypvs,1) - ypvs[1]) * 2000);
		keep = keep | c(TRUE, diff(levels)!=0);
		keep = which(keep);
		ypvs = ypvs[keep];
		xpvs = xpvs[keep];
		# 		rm(keep)
	} else {
		keep = seq_along(ypvs)
	}
	mx = head(xpvs,1)*1.05;
	my = max(mx*1.15,head(ypvs,1))*1.05;
	plot(NA,NA, ylim = c(0,my), xlim = c(0,mx), xaxs="i", yaxs="i", 
		  xlab = expression("- log"[10]*"(p-value), expected under null"),
		  ylab = expression("- log"[10]*"(p-value), observed"));
	# xlab = "-Log10(p-value), expected under null", ylab = "-Log10(p-value), observed");
	lines(c(0,mx),c(0,mx),col="grey")
	points(xpvs, ypvs, col = "red", pch = 19, cex = 0.25);
	
	if(!is.null(ci.level)) {
		if((ci.level>0)&(ci.level<1)) {
			quantiles = qbeta(p = rep(c(ci.level/2,1-ci.level/2),each=length(xpvs)), shape1 = keep, shape2 = ntests - keep + 1);
			quantiles = matrix(quantiles, ncol=2);
			
			lines( xpvs, -log10(quantiles[,1]), col="cyan4")
			lines( xpvs, -log10(quantiles[,2]), col="cyan4")
		}
	}
	legend("bottomright", c("P-values",sprintf("%.0f %% Confidence band",100-ci.level*100)),lwd = c(0,1), pch = c(19,NA_integer_), lty = c(0,1), col=c("red","cyan4"))
	if(length(pvalues)*2>ntests) {
		lambda = sprintf("%.3f",log10(pvalues[ntests/2]) / log10(0.5));
		legend("bottom", legend = bquote(lambda == .(lambda)), bty = "n")
		# 		text(mx, mx/2, bquote(lambda == .(lambda)), pos=2)
	}
}

ramwasAnnotateLocations = function(param, chr, pos){
	# Sanity check
	if(any(pos > 1e9L))
		stop('Annotation error: chromosome positions must be <= 1e9')
	
	# BiomaRt likes 1-22,X,Y, not chr1-chr22,chrX,chrY
	nochr = gsub("^chr","",chr);
	
	# Call biomaRt	
	{
		library(biomaRt)
		gene_ensembl = useMart(biomart=param$bimart, host = param$bihost, dataset=param$bidataset)
		bioresp = getBM(mart = gene_ensembl,
							 attributes = unique(c(
							 	param$biattributes,
							 	'chromosome_name',
							 	'start_position',
							 	'end_position')),
							 filters = c(list(chromosomal_region = paste0(nochr,':',pos,':',pos+1L)),
							 				param$bifilters)
		)
	}	
	
	if(nrow(bioresp) == 0) {
		rez = rep(list(rep("", length(chr))), length(param$biattributes))
		names(rez) = param$biattributes;
		return( data.frame(rez, stringsAsFactors = FALSE));
	}
	# Match Biomart response to chr/pos locations
	{
		# Transform chr/pos into single number coordinates
		chrunique = unique(nochr);
		
		tablepos = match(nochr, chrunique, nomatch = 0L) * 1e9 + pos;
		respchrn = match(bioresp$chromosome_name, chrunique, nomatch = 0L);
		resppos1 = respchrn * 1e9 + bioresp$start_position - param$biflank;
		resppos2 = respchrn * 1e9 + bioresp$end_position   + param$biflank;
		
		# Order CpGs by location
		ord = sort.list(tablepos);
		# tablepos[ord]
		
		### Find CpGs which match each returned gene
		### CpGs [fi1+1 : fi2] for each gene
		fi1 = findInterval( resppos1, tablepos[ord]+2) # offset by 1 for G in CpG, another 1 for strict inequality
		fi2 = findInterval( resppos2, tablepos[ord])
		
		## Enumerate all CpG-gene pairs
		## xx - CpG index (among sorted), factored for 'split' call 
		## yy - Gene index (within biomart response)
		xx = unlist(lapply(which(fi1<fi2),FUN=function(x){((fi1[x]+1):(fi2[x]))}));
		levels(xx) = paste0(seq_along(tablepos));
		class(xx) = 'factor'
		yy = rep(seq_along(fi1), times = fi2-fi1)
		
		spl = split(yy, xx)
		
		result = vector('list',length(param$biattributes));
		names(result) = param$biattributes;
		
		for( attr in param$biattributes) { # attr = param$biattributes[1]
			z = bioresp[[attr]]
			result[[attr]] = 
				sapply(spl, function(x){ paste0(z[x], collapse = '/') })
		}
		
		ord1 = seq_along(ord);
		ord1[ord] = ord1;
		
		# result2 = data.frame( chr, pos, lapply(result, `[`, ord1) )
		
		genes = data.frame(lapply(result, `[`, ord1), stringsAsFactors = FALSE);
	}
	return(genes);
}

ramwas5saveTopFindings = function(param){
	# library(filematrix)
	param = parameterPreprocess(param);
	
	message("Working in: ", param$dirmwas);
	
	message("Loading MWAS results");
	mwas = fm.load( paste0(param$dirmwas, "/Stats_and_pvalues") );
	
	message("Loading CpG locations");
	cpgloc = fm.load( paste0(param$dircoveragenorm, "/CpG_locations") );
	chrnames = readLines( paste0(param$dircoveragenorm, "/CpG_chromosome_names.txt") );
	
	message("Finding top MWAS hits");
	keep = which(mwas[,3] < param$toppvthreshold);
	ord = keep[sort.list(abs(mwas[keep,2]),decreasing = TRUE)];
	# mwas[ord,3]
	# mwas[ord[1],]
	
	toptable = data.frame( chr = chrnames[cpgloc[ord,1]],
								  position =     cpgloc[ord,2], 
								  tstat  = mwas[ord,2], 
								  pvalue = mwas[ord,3],
								  qvalue = mwas[ord,4]);
	
	# saveRDS(file = paste0(param$dirmwas,"/Top_tests.rds"), object = toptable);
	
	if( !is.null(param$biattributes) && (nrow(toptable)>0L) ) {
		message('Annotating top MWAS hits');
		bio = ramwasAnnotateLocations(param, chr = toptable$chr, pos = toptable$position);
		toptable = data.frame(toptable, bio);
	}
	
	message("Saving top MWAS hits");
	write.table(
		file = paste0(param$dirmwas,"/Top_tests.txt"),
		sep = '\t', quote = FALSE, row.names = FALSE, 
		x = toptable
	);
	return(invisible(NULL));
}

.ramwas5MWASjob = function(rng, param, mwascvrtqr, rowsubset){
	# rng = rangeset[[1]];
	# library(filematrix);
	fm = fm.open( paste0(param$dircoveragenorm, "/Coverage"), readonly = TRUE, lockfile = param$lockfile2);
	
	outmat = double(3*(rng[2]-rng[1]+1));
	dim(outmat) = c((rng[2]-rng[1]+1),3);
	
	# fmout = fm.open( paste0(param$dirmwas, "/Stats_and_pvalues"), lockfile = param$lockfile2);
	# covmat = 0;
	
	step1 = ceiling( 512*1024*1024 / nrow(fm) / 8);
	mm = rng[2]-rng[1]+1;
	nsteps = ceiling(mm/step1);
	for( part in 1:nsteps ) { # part = 1
		cat( part, "of", nsteps, "\n");
		fr = (part-1)*step1 + rng[1];
		to = min(part*step1, mm) + rng[1] - 1;
		
		slice = fm[,fr:to];
		if( !is.null(rowsubset) )
			slice = slice[rowsubset,];
		
		rez = testPhenotype(phenotype = param$covariates[[param$modeloutcome]],
								  data = slice, cvrtqr = mwascvrtqr)
		
		outmat[(fr:to) - (rng[1] - 1),] = cbind(rez[[1]], rez[[2]], rez[[3]]);
		
		fm$filelock$lockedrun( {
			cat(file = paste0(param$dirmwas,"/Log.txt"),
				 date(), ", Process ", Sys.getpid(), ", Job ", rng[3],
				 ", processing slice ", part, " of ", nsteps, "\n",
				 sep = "", append = TRUE);
		});
		rm(slice);
	}
	close(fm)
	
	if(rng[1]==1) {
		writeLines( con = paste0(param$dirmwas, "/DegreesOfFreedom.txt"), 
						text = as.character(c(rez$nVarTested, rez$dfFull)))
	}
	
	fmout = fm.open(paste0(param$dirmwas, "/Stats_and_pvalues"), lockfile = param$lockfile2);
	fmout[rng[1]:rng[2],1:3] = outmat;
	close(fmout);
	
	return("OK");
}

ramwas5MWAS = function( param ){
	# library(filematrix)
	param = parameterPreprocess(param);
	dir.create(param$dirmwas, showWarnings = FALSE, recursive = TRUE);
	
	parameterDump(dir = param$dirmwas, param = param,
					  toplines = c("dirmwas", "dirpca", "dircoveragenorm",
					  				 "filecovariates", "covariates",
					  				 "modeloutcome", "modelcovariates", "modelPCs",
					  				 "qqplottitle",
					  				 "diskthreads"));
	
	
	message("Preparing for MWAS");
	
	### Kill NA outcomes
	if(any(is.na(param$covariates[[ param$modeloutcome ]]))){
		param$covariates = data.frame(lapply( param$covariates, `[`, !is.na(param$covariates[[ param$modeloutcome ]])));
	}
	### Get and match sample names
	{
		message("Matching samples in covariates and data matrix");
		rez = .matchCovmatCovar( param ); # rez = ramwas:::.matchCovmatCovar( param );
		rowsubset = rez$rowsubset;
		ncpgs     = rez$ncpgs;
		cvsamples = param$covariates[[1]];
		rm(rez);
	} # rowsubset, ncpgs, cvsamples
	
	### Prepare covariates, defactor, 
	{
		message("Preparing covariates (splitting dummy variables, orthonormalizing)");
		mwascvrtqr = .getCovariates(param, rowsubset);
		# mwascvrtqr = ramwas:::.getCovariates(param, rowsubset);
		# cvrtqr = t(orthonormalizeCovariates( param$covariates[ param$modelcovariates ] ));
	} # cvrtqr
	
	
	### Outpout matrix. Cor / t-test / p-value / q-value
	### Outpout matrix. R2  / F-test / p-value / q-value
	{
		message("Creating output matrix");
		fm = fm.create( paste0(param$dirmwas, "/Stats_and_pvalues"), nrow = ncpgs, ncol = 4);
		if( !is.character( param$covariates[[param$modeloutcome]] ) ) {
			colnames(fm) = c("cor","t-test","p-value","q-value");
		} else {
			colnames(fm) = c("R-squared","F-test","p-value","q-value");
		}
		close(fm);
	}
	
	### Running MWAS in parallel
	{
		message("Running MWAS");
		cat(file = paste0(param$dirmwas,"/Log.txt"), 
			 date(), ", Running methylome-wide association study.", "\n", sep = "", append = FALSE);
		if( param$diskthreads > 1 ) {
			rng = round(seq(1, ncpgs+1, length.out = param$diskthreads+1));
			rangeset = rbind( rng[-length(rng)], rng[-1]-1, seq_len(param$diskthreads));
			rangeset = lapply(seq_len(ncol(rangeset)), function(i) rangeset[,i])
			
			if(param$usefilelock) param$lockfile2 = tempfile();
			# library(parallel);
			cl = makeCluster(param$diskthreads);
			clusterExport(cl, "testPhenotype")
			clusterApplyLB(cl, rangeset, .ramwas5MWASjob, 
								param = param, mwascvrtqr = mwascvrtqr, rowsubset = rowsubset);
			stopCluster(cl);
			rm(cl, rng, rangeset);
			.file.remove(param$lockfile2);
		} else {
			covmat = .ramwas5MWASjob( rng = c(1, ncpgs, 0), param, mwascvrtqr, rowsubset);
		}
		cat(file = paste0(param$dirmwas,"/Log.txt"), 
			 date(), ", Done running methylome-wide association study.", "\n", sep = "", append = TRUE);
	}	
	
	### Fill in FDR column
	{
		message("Calculating FDR (q-values)");
		fm = fm.open( paste0(param$dirmwas, "/Stats_and_pvalues"));
		pvalues = fm[,3];
		pvalues[pvalues==0] = .Machine$double.xmin;
		fm[,4] = pvalue2qvalue( pvalues );
		close(fm);
		
		rm(fm);
	} # sortedpv
	
	### QQ-plot
	{
		message("Creating QQ-plot");
		pdf(paste0(param$dirmwas, "/QQ_plot.pdf"),7,7);
		qqPlotFast(pvalues);
		title(param$qqplottitle);
		dev.off();
	}
	ramwas5saveTopFindings(param);
	return(invisible(NULL));
}
