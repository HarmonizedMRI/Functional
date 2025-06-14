# Harmonized functional MRI with Pulseq

Pooling functional MRI data from different sites and points in time 
should allow for increased statistical power, 
provided that the imaging experiment can be conducted in a known and reproducible way. 
Unfortunately, this has so far proven difficult, 
since the details of the vendor-provided fMRI acquisition and reconstruction software 
are generally not known to the researcher.

We have developed a fully **vendor-agnostic and portable fMRI protocol**
that ensures identical sequence execution and image reconstruction across different scanners, 
and across scanner software upgrades. 
The acquisition sequence is defined in a simple (and human readable) text file in the 
[Pulseq](https://pulseq.github.io/)
file format, 
and sequence execution on real hardware is made possible with sequence-agnostic interpreters that we provide.
This ensures transparent and optimally reproducible experimental conditions across sites.
**Our protocol is fully open-source and available to the broader research community**,
and we hope that it will become the new standard for future multi-site functional MRI studies.

So far, our protocol has been tested Siemens and GE scanners, but other vendors are adding (or have already added)
Pulseq support and we encourage you to reach out to your vendor representative for the latest information.

![HarmonizedMRI](images/hmri.jpg)


## Getting started

### For PIs preparing an NIH grant application:
We encourage you to write Pulseq fMRI into your next grant application!
We believe that Pulseq is the best technology for achieving transparent and reproducible MRI, 
providing a solid foundation for the best science; and that grant reviewers will agree.
At [this link](https://drive.google.com/drive/folders/1SaivtmjwFJ_OsU8SBrE1ub1DmhPF6p6W?usp=sharing)
you will find **NIH grant text templates** to help you get started.
There you will also find **IRB application example text** that you may find useful
when applying for local IRB approval for a study that uses Pulseq MRI protocols.

### For pulse sequence developers/maintainers:
If you want to test the acquisition and/or reconstruction protocol:

1. Contact the HarmonizedMRI study team for access to the interpreter for your scanner.

2. Ask the study team for the sequence file 'smsepi.seq', 
or create your own using the 'writeEPI.m' MATLAB function that we provide.
The run it on your scanner.

3. Reconstruct the data using slice GRAPPA code that we provide.

For more information, see the ./example/ folder in the 
[SMS-EPI](https://github.com/HarmonizedMRI/SMS-EPI)
Github repository.


## Beta testers wanted!

If you have an interest in multi-site fMRI or want to prototype new EPI fMRI methods,
our Pulseq SMS-EPI fMRI protocol may be for you.
If you'd like to give it a quick try for evaluation purposes, 
or are already sure you want to use it for your fMRI studies, 
[contact us by email](mailto:jfnielse@umich.edu) and we will work with you
to install the Pulseq interpreters and the sequence and reconstruction code.  
At present, we ask that if you plan to use our Pulseq protocol in your fMRI studies, 
your scanner is also equipped with the corresponding SMS-EPI product sequence.

