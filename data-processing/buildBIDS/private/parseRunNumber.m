function runNumber = parseRunNumber(filename, prefix)
%PARSERUNNUMBER Extract run number from PREFIXn.nii.
%
% Examples:
%   parseRunNumber('task_run3.nii', 'task_run') -> 3
%   parseRunNumber('rest_run2.nii', 'rest_run') -> 2

arguments
    filename (1,:) char
    prefix   (1,:) char
end

expression = sprintf( ...
    '^%s(\\d+)\\.nii$', ...
    regexptranslate('escape', prefix));

tokens = regexp( ...
    filename, ...
    expression, ...
    'tokens', ...
    'once');

if isempty(tokens)
    runNumber = [];
else
    runNumber = str2double(tokens{1});
end

