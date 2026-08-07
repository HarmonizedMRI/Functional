function info = parseSessionName(sessionName, srcRoot, bidsRoot)
%PARSESESSIONNAME Parse HarmonizedMRI internal session naming.
%
% Example:
%
%   sub00012-umich-mr750-20250115
%
% becomes
%
%   sub-00012
%   ses-umichmr75020250115

arguments
    sessionName (1,:) char
    srcRoot     (1,:) char
    bidsRoot    (1,:) char
end

tokens = regexp( ...
    sessionName, ...
    '^sub(\d+)-([A-Za-z0-9]+)-([A-Za-z0-9]+)-(\d{8})$', ...
    'tokens', ...
    'once');

if isempty(tokens)
    error( ...
        'parseSessionName:InvalidSessionName', ...
        'Invalid session name: %s', ...
        sessionName);
end

subjectNumber = str2double(tokens{1});
site          = lower(tokens{2});
scanner       = lower(tokens{3});
date          = tokens{4};

info.sessionName = sessionName;

info.sub = sprintf( ...
    'sub-%05d', ...
    subjectNumber);

info.ses = sprintf( ...
    'ses-%s%s%s', ...
    site, ...
    scanner, ...
    date);

info.site = site;
info.scanner = scanner;
info.date = date;

info.srcDir = fullfile( ...
    srcRoot, ...
    sessionName);

info.subjectDir = fullfile( ...
    bidsRoot, ...
    info.sub);

info.sessionDir = fullfile( ...
    info.subjectDir, ...
    info.ses);

