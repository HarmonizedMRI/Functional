function buildBIDS(srcRoot, srcBIDS)
%BUILDBIDS Build source BIDS dataset from internal HarmonizedMRI data.
%
% Example:
%
%   buildBIDS( ...
%       '/home/jon/data/srcRoot', ...
%       '/home/jon/data/srcBIDS');

arguments
    srcRoot (1,:) char
    srcBIDS (1,:) char
end

sessions = findSessions(srcRoot);

for iSession = 1:numel(sessions)

    sessionName = sessions(iSession).name;

    info = parseSessionName( ...
        sessionName, ...
        srcRoot, ...
        srcBIDS);

    fprintf('\nProcessing %s\n', sessionName);

    copySessionToBIDS(info);

end

