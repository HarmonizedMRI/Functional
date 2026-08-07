function copyAnat(info)
%COPYANAT Copy T1-weighted anatomical data into BIDS.

srcDir = fullfile(info.srcDir, 'anat');

if ~isfolder(srcDir)
    warning('copyAnat:MissingDirectory', ...
        'Anatomical directory not found: %s', srcDir);
    return
end

copyIfPresent( ...
    fullfile(srcDir, 'T1w.nii.gz'), ...
    makeBidsPath(info, 'anat', 'T1w.nii.gz'));

copyIfPresent( ...
    fullfile(srcDir, 'T1w.json'), ...
    makeBidsPath(info, 'anat', 'T1w.json'));

