function buildBIDS(srcRoot, bidsRoot)
%BUILDBIDS Build source BIDS dataset from internal HarmonizedMRI data.
%
% Example:
%
%   buildBIDS( ...
%       '/home/jon/data/srcRoot', ...
%       '/home/jon/data/bidsRoot');

arguments
    srcRoot (1,:) char
    bidsRoot (1,:) char
end

sessions = findSessions(srcRoot);

for iSession = 1:numel(sessions)

    sessionName = sessions(iSession).name;

    info = parseSessionName( ...
        sessionName, ...
        srcRoot, ...
        bidsRoot);

    fprintf('\nProcessing %s\n', sessionName);

    copySessionToBIDS(info);
    copyCalibration(info);

end

