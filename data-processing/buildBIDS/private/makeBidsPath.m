function destination = makeBidsPath(info, modality, suffix)
%MAKEBIDSPATH Construct a BIDS destination filename.

arguments
    info     (1,1) struct
    modality (1,:) char
    suffix   (1,:) char
end

filename = sprintf('%s_%s_%s', ...
    info.sub, ...
    info.ses, ...
    suffix);

destinationDir = fullfile( ...
    info.sessionDir, ...
    modality);

ensureDirectory(destinationDir);

destination = fullfile( ...
    destinationDir, ...
    filename);

