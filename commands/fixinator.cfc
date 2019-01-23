/**
 * Scans CFML Source Code for Issues
 * .
 * Examples
 * {code:bash}
 * fixinator dirName
 * {code}
 **/
component extends="commandbox.system.BaseCommand" aliases="combover" excludeFromHelp=false {

	property inject="FixinatorClient@fixinator" name="fixinatorClient";
	property inject="FixinatorReport@fixinator" name="fixinatorReport";
	property inject="progressBarGeneric" name="progressBar";

	/**
	* @path.hint A file or directory to scan
	* @resultFile.hint A file path to write JSON results to
	* @resultFormat.hint The format to write the results in [json]
	* @verbose.hint When false limits the output
	* @listBy.hint Show results by type or file
	* @severity.hint The minimum severity warn, low, medium or high
	* @confidence.hint The minimum confidence level none, low, medium or high
	* @ignoreScanners.hint A comma seperated list of scanner ids to ignore
	* @autofix.hint Use either off, prompt or automatic
	**/
	function run( required string path, string resultFile, string resultFormat="json", boolean verbose=true, string listBy="type", string severity="low", string confidence="high", string ignoreScanners="", autofix="off")  {
		var fileInfo = "";
		var severityLevel = 1;
		var confLevel = 1;
		var config = {};
		var toFix = [];
		if (arguments.verbose) {
			print.greenLine("fixinator v1.0.0 built by Foundeo Inc.").line();
			print.grayLine("    ___                      _             ");
			print.grayLine("   / __)                    | |            ");		
			print.grayLine(" _| |__ ___  _   _ ____   __| |_____  ___  ");
			print.grayLine("(_   __) _ \| | | |  _ \ / _  | ___ |/ _ \ ");
			print.grayLine("  | | | |_| | |_| | | | ( (_| | ____| |_| |");
			print.grayLine("  |_|  \___/|____/|_| |_|\____|_____)\___/ ");
			print.grayLine("                                         inc.");
			print.line();
		}

		arguments.path = fileSystemUtil.resolvePath( arguments.path );



		if (!listFindNoCase("warn,low,medium,high", arguments.severity)) {
			print.redLine("Invalid minimum severity level, use: warn,low,medium,high");
			return;
		} else {
			config.minSeverity = arguments.severity;
		}

		if (!listFindNoCase("none,low,medium,high", arguments.confidence)) {
			print.redLine("Invalid minimum confidence level, use: none,low,medium,high");
			return;
		} else {
			config.minConfidence = arguments.confidence;
		}

		if (len(arguments.ignoreScanners)) {
			config.ignoreScanners = listToArray(replace(arguments.ignoreScanners, " ", "", "ALL"));
		}


		if (!fileExists(arguments.path) && !directoryExists(arguments.path)) {
			print.boldRedLine("Sorry: #arguments.path# is not a file or directory.");
			return;
		}

		fileInfo = getFileInfo(arguments.path);
		
		if (!fileInfo.canRead) {
			print.boldRedLine("Sorry: No read permission for source path");
			return;
		}

		
		
		try {
			
			if (arguments.verbose) {
				//show status dots
				variables.fixinatorRunning = true;
				variables.fixinatorThread = "fixinator" & createUUID();
				
				thread action="run" name="#variables.fixinatorThread#" print="#print#" {
	 				// do single thread stuff 
	 				thread.i = 0;
	 				for (thread.i=0;thread.i<50;thread.i++) {
	 					attributes.print.text(".").toConsole();
	 					thread action="sleep" duration="1000";
	 					cflock(name="fixinator-command-lock", type="readonly", timeout=1) {
	 						if (!variables.fixinatorRunning) {
	 							break;
	 						}
	 					}
	 				}
				}
			}

			local.results = fixinatorClient.run(path=arguments.path,config=config);	

			if (arguments.verbose) {
				//stop status indicator
				cflock(name="fixinator-command-lock", type="exclusive", timeout="5") {
					variables.fixinatorRunning = false;

				}
				thread action="terminate", name="#variables.fixinatorThread#";
				print.line();
			}
			/*
			if (arguments.verbose) {
					//show progress bars
					//job.start("Scanning " & arguments.path);
				progressBar.update( percent=0 );
				local.results = fixinatorClient.run(path=arguments.path,config=config, progressBar=progressBar);	
				//job.complete();	
			} else {
				//no progress bar or interactive job output
				local.results = fixinatorClient.run(path=arguments.path,config=config);	
			}*/
			

			
		} catch(err) {
			if (err.type == "FixinatorClient") {
				print.line().boldRedLine("---- Fixinator Client Error ----").line();
				print.redLine(err.message);
				if (structKeyExists(err, "detail")) {
					print.whiteLine(err.detail);	
				}
				return;
			} else {
				rethrow;
			}
		}
		


		if (arrayLen(local.results.results) == 0 && arrayLen(local.results.warnings) == 0)   {
			print.boldGreenLine("0 Issues Found");
		} else {
			print.boldRedLine("FINDINGS: " & arrayLen(local.results.results));

			if (len(arguments.resultFile)) {
				arguments.resultFile = fileSystemUtil.resolvePath( arguments.resultFile );
				fixinatorReport.generateReport(resultFile=arguments.resultFile, format=arguments.resultFormat, listBy=arguments.listBy, data=local.results);
			}

			local.resultsByType = {};
			for (local.i in local.results.results) {
				local.typeKey = "";
				if (arguments.listBy == "type") {
					local.typeKey = local.i.id;
				} else {
					local.typeKey = local.i.path;
				}
				if (!local.resultsByType.keyExists(local.typeKey)) {
					local.resultsByType[local.typeKey] = [];
				}
				arrayAppend(local.resultsByType[local.typeKey], local.i);
			}

			for (local.typeKey in local.resultsByType) {
				print.boldRedLine(local.typeKey);
				for (local.i in local.resultsByType[local.typeKey]) {
					if (arguments.listBy == "type") {
						local.line = "#local.i.path#:#local.i.line#";
						
					} else {
						local.line = "[#local.i.id#] on line #local.i.line#";
					}
					if (local.i.severity == 3) {
						print.redLine("#chr(9)##local.line#");
					} else if (local.i.severity == 2) {
						print.magentaLine("#chr(9)##local.line#");
					} else if (local.i.severity == 1) {
						print.aquaLine("#chr(9)##local.line#");
					} else {
						print.yellowLine("#chr(9)##local.line#");
					}
					
					if (arguments.verbose) {
						print.line();
						local.conf = "";
						if (local.i.keyExists("confidence") && local.i.confidence > 0 && local.i.confidence <=3) {
							local.confMap = ["low confidence", "medium confidence", "high confidence"];
							local.conf = " " & local.confMap[local.i.confidence];
						}
						if (local.i.severity == 3) {
							print.redLine("#chr(9)#[HIGH] #local.i.message##local.conf#");
						} else if (local.i.severity == 2) {
							print.magentaLine("#chr(9)#[MEDIUM] #local.i.message##local.conf#");
						} else if (local.i.severity == 1) {
							print.aquaLine("#chr(9)#[LOW] #local.i.message##local.conf#");
						} else {
							print.yellowLine("#chr(9)#[WARN] #local.i.message##local.conf#");
						}
						if (len(local.i.context)) {
							print.greyLine("#chr(9)##local.i.context#");
						}
						if (local.i.keyExists("link") && len(local.i.link)) {
							print.greyLine(chr(9) & local.i.link);
						}
						if (local.i.keyExists("fixes") && arrayLen(local.i.fixes) > 0) {
							print.greyLine("#chr(9)#Possible Fixes:");
							local.fixIndex = 0;
							local.fixOptions = "";
							for (local.fix in local.i.fixes) {
								local.fixIndex++;
								local.fixOptions = listAppend(local.fixOptions, local.fixIndex);
								print.greyLine(chr(9)&chr(9)&local.fixIndex&": "&local.fix.title & ": " & local.fix.fixCode);
							}
							if (arguments.autofix == "prompt") {
								print.toConsole();
								/*
								local.fix = multiselect()
								    .setQuestion( 'Do you want to fix this?' )
    								.setOptions( listAppend(local.fixOptions, "skip") )
    								.ask();
    							*/
    							local.fix = ask(message="Do you want to fix this? Enter [1-#arrayLen(local.i.fixes)#] or no: ");


								if (isNumeric(local.fix) && local.fix >= 1 && local.fix <= arrayLen(local.i.fixes)) {
									toFix.append({"fix":local.i.fixes[local.fix], "issue":local.i});
								} 

							}
						}
					}
				}
			}
			/*
			for (local.i in local.results.results) {
				if (arguments.verbose) {
					print.line();
					print.redLine(local.i.message);
					print.greyLine("#chr(9)##local.i.path#:#local.i.line#");
					if (len(local.i.context)) {
						print.greyLine("#chr(9)##local.i.context#");
					}
				} else {
					print.redLine("[#local.i.id#] #local.i.path#:#local.i.line#");
				}
			}*/
			if (arguments.verbose && arrayLen(local.results.warnings)) {
				print.line();
				print.boldOrangeLine("WARNINGS");
				for (local.w in local.results.warnings) {
					print.grayLine(serializeJSON(local.w));
				}
			}

			if (arrayLen(toFix) > 0) {
				print.line();
				print.boldOrangeLine("FIXING #arrayLen(toFix)# issues");
				local.fixResults = fixinatorClient.fixCode(basePath=arguments.path, fixes=toFix);

			}


		}

	}

}