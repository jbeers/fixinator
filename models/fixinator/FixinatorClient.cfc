component singleton="true" {

	variables.maxPayloadSize = 1 * 512 * 1024;//half mb
	variables.apiURL = "https://api.fixinator.app/v1/scan";
	variables.system = createObject("java", "java.lang.System");
	if (!isNull(variables.system.getenv("FIXINATOR_API_URL"))) {
		variables.apiURL = variables.system.getenv("FIXINATOR_API_URL");
	}
	variables.clientVersion = "1.0.0";

	public function run(string path, struct config={}, any progressBar="", any job="") {
		var files = "";
		var payload = {"config"=getDefaultConfig(), "files"=[]};
		var results = {"warnings":[], "results":[], "payloads":[]};
		var size = 0;
		var pathData = getFileInfo(arguments.path);
		var fileCounter = 0;
		var percentValue = 0;
		var hasProgressBar = isObject(arguments.progressBar);
		var hasJob = isObject(arguments.job);

		if (fileExists(getDirectoryFromPath(arguments.path) & ".fixinator.json")) {
			local.fileConfig = fileRead(getDirectoryFromPath(arguments.path) & ".fixinator.json");
			if (isJSON(local.fileConfig)) {
				local.fileConfig = deserializeJSON(local.fileConfig);
				structAppend(payload.config, local.fileConfig, true);
			} else {
				throw(message="Invalid .fixinator.json config file, was not valid JSON");
			}
		}

		structAppend(payload.config, arguments.config, true);
		if (pathData.type == "file") {
			files = [arguments.path];
		} else {
			files = directoryList(arguments.path, true, "path");
			files = filterPaths(arguments.path, files, payload.config);	
		}
		for (local.f in files) {
			fileCounter++;
			local.fileInfo = getFileInfo(local.f);
			if (local.fileInfo.canRead) {
				if (local.fileInfo.size > variables.maxPayloadSize) {
					results.warnings.append( { "message":"File was too large, #local.fileInfo.size# bytes, max: #variables.maxPayloadSize#", "path":local.f } );
					continue;
				} else {
					local.ext = listLast(local.f, ".");
					if (size + local.fileInfo.size > variables.maxPayloadSize) {
						if (hasJob) {
							job.start( ' Scanning Payload (#arrayLen(payload.files)# of #arrayLen(files)# files) this may take a sec...' );
							if (hasProgressBar) {
								progressBar.update( percent=percentValue, currentCount=fileCounter, totalCount=arrayLen(files) );	
							}
							local.msStart = getTickCount();
						}
						local.result = sendPayload(payload);
						if (hasJob) {
							job.addSuccessLog( ' Scan Payload Complete, took #getTickCount()-local.msStart#ms ' );
							job.complete(dumpLog=false);

						}
						arrayAppend(results.results, local.result.results, true);
						payload.result = local.result;
						//arrayAppend(results.payloads, payload);
						size = 0;
						payload = {"config"=arguments.config, "files"=[]};
					} else {
						size+= local.fileInfo.size;
						payload.files.append({"path":replace(local.f, arguments.path, ""), "data":(local.ext == "jar") ? "" : fileRead(local.f), "sha1":fileSha1(local.f)});
					}
				}
			} else {
				results.warnings.append( { "message":"Missing Read Permission", "path":local.f } );
			}
			percentValue = int( (fileCounter/arrayLen(files)) * 90);
			if (percentValue >= 100) {
				percentValue = 90;
			}
			if (hasProgressBar) {
				progressBar.update( percent=percentValue, currentCount=fileCounter, totalCount=arrayLen(files) );	
			}
		}
		if (arrayLen(payload.files)) {
			if (hasJob) {
				job.start( ' Scanning Payload (#arrayLen(payload.files)# of #arrayLen(files)# files) this may take a sec...' );
				local.msStart = getTickCount();
			}
			local.result = sendPayload(payload);
			if (hasJob) {
				job.addSuccessLog ( ' Scan Payload Complete, took #getTickCount()-local.msStart#ms ' );
				job.complete(dumpLog=false);
			}
			payload.result = local.result;
			//arrayAppend(results.payloads, payload);
			arrayAppend(results.results, local.result.results, true);
		}
		structDelete(results, "payloads");
		if (hasProgressBar) {
			progressBar.update( percent=100, currentCount=arrayLen(files), totalCount=arrayLen(files) );	
		}
		
		return results;
	}

	public function sendPayload(payload, isRetry=0) {
		var httpResult = "";
		cfhttp(url=variables.apiURL, method="POST", result="httpResult") {
			cfhttpparam(type="header", name="Content-Type", value="application/json");
			cfhttpparam(type="header", name="x-api-key", value=getAPIKey());
			cfhttpparam(type="header", name="X-Client-Version", value=variables.clientVersion);
			cfhttpparam(value="#serializeJSON(payload)#", type="body");
		}
		if (httpResult.statusCode contains "403") {
			//FORBIDDEN -- API KEY ISSUE
			if (getAPIKey() == "UNDEFINED") {
				throw(message="Fixinator API Key must be defined in an environment variable called FIXINATOR_API_KEY", detail="If you have already set the environment variable you may need to reopen your terminal or command prompt window. Please visit https://fixinator.app/ for more information", type="FixinatorClient");
			} else {
				throw(message="Fixinator API Key (#getAPIKey()#) is invalid, disabled or over the API request limit. Please contact Foundeo Inc. for assistance. Please provide your API key in correspondance. https://foundeo.com/contact/ ", detail="#httpResult.statusCode# #httpResult.fileContent#", type="FixinatorClient");
			}
		} else if (httpResult.statusCode contains "429") { 
			//TOO MANY REQUESTS
			if (arguments.isRetry == 1) {
				throw(message="Fixinator API Returned 429 Status Code (Too Many Requests). Please try again shortly or contact Foundeo Inc. if the problem persists.");
			} else {
				//retry it once
				return sendPayload(payload=arguments.payload, isRetry=1);
			}
		} else if (httpResult.statusCode contains "502") { 
			//BAD GATEWAY - lambda timeout issue
			if (arguments.isRetry == 1) {
				throw(message="Fixinator API Returned 502 Status Code (Bad Gateway). Please try again shortly or contact Foundeo Inc. if the problem persists.");
			} else {
				//retry it once
				return sendPayload(payload=arguments.payload, isRetry=1);
			}
		}
		if (!isJSON(httpResult.fileContent)) {
			throw(message="API Result was not valid JSON", detail=httpResult.fileContent);
		}
		if (httpResult.statusCode does not contain "200") {
			throw(message="API Returned non 200 Status Code (#httpResult.statusCode#)", detail=httpResult.fileContent, type="FixinatorClient");
		}
		
		return deserializeJSON(httpResult.fileContent);
	}

	public function getAPIKey() {
		if (!isNull(variables.system.getenv("FIXINATOR_API_KEY"))) {
			return variables.system.getenv("FIXINATOR_API_KEY");
		} else {
			return "UNDEFINED";
		}
	}

	public function filterPaths(baseDirectory, paths, config) {
		var f = "";
		var ignoredPaths = [];
		var filteredPaths = [];
		if (arguments.config.keyExists("ignoredPaths")) {
			ignoredPaths = arguments.config.ignoredPaths;
		}
		for (f in paths) {
			if (directoryExists(f)) {
				continue;
			}
			local.p = replace(f, arguments.baseDirectory, "");
			local.skip = false;
			local.fileName = getFileFromPath(f);
			local.ext = listLast(local.fileName, ".");

			//certain extensions are ignored
			if (listFindNoCase("jpg,png,txt,pdf,doc,docx,gif,css,zip,bak,exe,pack", local.ext)) {
				continue; //skip
			}


			for (local.ignore in ignoredPaths) {
				if (find(local.ignore, local.p) != 0) {
					local.skip = true;
					continue;
				}
			}

			if (!local.skip) {
				arrayAppend(filteredPaths, f);
			}
		}
		return filteredPaths;
	}

	public function fixCode(basePath, fixes) {
		var fix = "";
		var basePathInfo = getFileInfo(arguments.basePath);
		//sort issues by file then line number
		arraySort(
  		  arguments.fixes,
    		function (e1, e2){
    			if (e1.issue.path == e2.issue.path) {
    				return e1.issue.line < e2.issue.line;
    			} else {
    				return compare(e1.issue.path, e2.issue.path);	
    			}
        		
    		}
		);
		local.lastFile = "";
		local.filePositionOffset = 0;
		for (fix in arguments.fixes) {
			if (basePathInfo.type == "file") {
				local.filePath = arguments.basePath;
			} else {
				local.filePath = arguments.basePath & fix.issue.path;
			}


			if (!fileExists(local.filePath)) {
				throw(message="Unable to autofix, file: #local.filePath# does not exist");
			}

			if (local.lastFile != local.filePath) {
				local.lastFile = local.filePath;
				local.filePositionOffset = 0;
				local.fileContent = fileRead(local.filePath);
			}

			/*
				 fix.fix = {
					fixCode=codeToReplaceWith
					replacePosition=posInFile, 
					replaceString="fix"}
			*/
			
			local.fixStartPos = local.filePositionOffset + fix.fix.replacePosition;
			local.fileSnip = mid(local.fileContent, local.fixStartPos, len(fix.fix.replaceString));
			if (local.fileSnip != fix.fix.replaceString) {
				throw(message="Snip does not match: #local.fileSnip# expected: #fix.fix.replaceString# #serializeJSON(local)# FPO:#local.filePositionOffset# FSP:#local.fixStartPos#  #local.fileContent# ");
			} else {
				local.prefix = mid(local.fileContent, 1, local.fixStartPos-1);
				local.suffix = mid(local.fileContent, local.fixStartPos + len(local.fix.fix.replaceString), len(fileContent)- local.fixStartPos + len(local.fix.fix.replaceString));
				local.fileContent = local.prefix & local.fix.fix.fixCode & local.suffix;

				local.filePositionOffset = ( len(fix.fix.fixCode) - len(fix.fix.replaceString) );

				//throw(message="FPO:#local.filePositionOffset# FileContent:#local.fileContent#");

				if (fix.fix.replaceString contains chr(13)) {
					throw(message="rs contains char(13)");
				}
				if (fix.fix.replaceString contains chr(10)) {
					throw(message="rs contains char(13)");
				}

				fileWrite(local.filePath, local.fileContent);

			}

			

		}
	}



	public struct function getDefaultConfig() {
		return {
			"ignoredPaths":["/.git/","\.git\","/.svn/","\.svn\", ".git/"],
			"ignoredExtensions":[],
			"ignoreScanners":[],
			"minSeverity": "low",
			"minConfidence": "low"
		};
	}

	public string function fileSha1(path) {
		var fIn = createObject("java", "java.io.FileInputStream").init(path);
		return createObject("java", "org.apache.commons.codec.digest.DigestUtils").sha1Hex(fIn);
	}



}