function copyFmap(info)
%COPYFMAP Copy canonical field-map data into BIDS.

arguments
    info (1,1) struct
end

srcDir = fullfile(info.srcDir, 'fmap');

if ~isfolder(srcDir)
    warning('copyFmap:MissingDirectory', ...
        'Field-map directory not found: %s', srcDir);
    return
end

files = {
    'fieldmap.nii.gz'
    'fieldmap.json'
    'magnitude.nii.gz'
    'magnitude.json'
};

for i = 1:numel(files)

    src = fullfile(srcDir, files{i});

    if ~isfile(src)
        warning('copyFmap:MissingFile', ...
            'Field-map file not found: %s', src);
        continue
    end

    dst = makeBidsPath(info, 'fmap', files{i});

    copyIfPresent(src, dst);

end

