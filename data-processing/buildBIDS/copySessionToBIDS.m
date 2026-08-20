function copySessionToBIDS(info)
%COPYSESSIONTOBIDS Copy one internal session into the source BIDS dataset.

arguments
    info (1,1) struct
end

copyAnat(info);
copyFmap(info);

% copy BOLD. 
% Optional inputs apply only to Pulseq scans (needed for B0 distortion correction).
copyBOLD(info, ...
    PhaseEncodingDirection="j-", ...
    TotalReadoutTime=0.0522);

