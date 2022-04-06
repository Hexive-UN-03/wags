
rule fastqc:
    input:
        unpack(get_fastq)
    output:
        r1_zip  = S3.remote("{bucket}/wgs/{breed}/{sample_name}/fastqc/{sample_name}/{flowcell}/{readgroup_name}_R1_fastqc.zip"),
        r1_html = S3.remote("{bucket}/wgs/{breed}/{sample_name}/fastqc/{sample_name}/{flowcell}/{readgroup_name}_R1_fastqc.html"),
        r2_zip  = S3.remote("{bucket}/wgs/{breed}/{sample_name}/fastqc/{sample_name}/{flowcell}/{readgroup_name}_R2_fastqc.zip"),
        r2_html = S3.remote("{bucket}/wgs/{breed}/{sample_name}/fastqc/{sample_name}/{flowcell}/{readgroup_name}_R2_fastqc.html"),
    params:
       #flowcell = lambda wildcards: units.loc[units['readgroup_name'] == wildcards.readgroup_name,'flowcell'].values[0],
        outdir = "{bucket}/wgs/{breed}/{sample_name}/fastqc/{sample_name}/{flowcell}",
        r1_html = lambda wildcards, input: os.path.basename(input.r1.replace(".fastq.gz","_fastqc.html")),
        r1_zip  = lambda wildcards, input: os.path.basename(input.r1.replace(".fastq.gz","_fastqc.zip")),
        r2_html = lambda wildcards, input: os.path.basename(input.r2.replace(".fastq.gz","_fastqc.html")),
        r2_zip  = lambda wildcards, input: os.path.basename(input.r2.replace(".fastq.gz","_fastqc.zip")),
    benchmark:
        "{bucket}/wgs/{breed}/{sample_name}/fastqc/{sample_name}/{flowcell}/{readgroup_name}.fastqc.benchmark.txt"
    threads: 6
    resources:
         time   = 360,
         mem_mb = 6000, 
    shell:
        '''
            set -e

            fastqc -t {threads} \
                --outdir {params.outdir} \
                {input.r1} {input.r2}

            mv {params.outdir}/{params.r1_html} {output.r1_html}
            mv {params.outdir}/{params.r2_html} {output.r2_html}
            mv {params.outdir}/{params.r1_zip} {output.r1_zip}
            mv {params.outdir}/{params.r2_zip} {output.r2_zip}
        '''

rule flagstat:
    input:
        final_bam = S3.remote("{bucket}/wgs/{breed}/{sample_name}/{ref}/bam/{sample_name}.{ref}.bam"),
        final_bai = S3.remote("{bucket}/wgs/{breed}/{sample_name}/{ref}/bam/{sample_name}.{ref}.bai"),
    output:
        flagstat = S3.remote("{bucket}/wgs/{breed}/{sample_name}/{ref}/qc/{sample_name}.{ref}.flagstat.txt"),
    benchmark:
        "{bucket}/wgs/{breed}/{sample_name}/{ref}/qc/{sample_name}.flagstat.benchmark.txt"
    threads: 8
    resources:
         time   = 60,
         mem_mb = 12000
    shell:
        '''
            samtools flagstat \
                {input.final_bam} \
                --thread 8 \
                > {output.flagstat}
        '''

#rule coverage_depth:
#    input:
#        final_bam  = S3.remote("{bucket}/wgs/{breed}/{sample_name}/{ref}/bam/{sample_name}.{ref}.bam"),
#        final_bai  = S3.remote("{bucket}/wgs/{breed}/{sample_name}/{ref}/bam/{sample_name}.{ref}.bai"),
#        acgt_ivals = "{bucket}/wgs/{breed}/{sample_name}/{ref}/gvcf/hc_intervals/acgt.N50.interval_list",
#    output:
#        doc_smry = S3.remote("{bucket}/wgs/{breed}/{sample_name}/{ref}/qc/{sample_name}.{ref}.doc.sample_summary"),
#        doc_stat = S3.remote("{bucket}/wgs/{breed}/{sample_name}/{ref}/qc/{sample_name}.{ref}.doc.sample_statistics"),
#    params:
#        doc_base   = "{bucket}/wgs/{breed}/{sample_name}/{ref}/qc/{sample_name}.{ref}.doc",
#        java_opt   = "-Xmx32000m",
#        ref_fasta  = config['ref_fasta'],
#        tmp_dir    = "/dev/shm/{sample_name}_{ref}.doc.tmp"
#    benchmark:
#        "{bucket}/wgs/{breed}/{sample_name}/{ref}/qc/{sample_name}.doc.benchmark.txt"
#    threads: 8
#    resources:
#         time   = 1440,
#         mem_mb = 32000
#    shell:
#        '''
#            mkdir -p {params.tmp_dir}
#
#            gatk DepthOfCoverage --java-options {params.java_opt} \
#                -I {input.final_bam} \
#                -R {params.ref_fasta} \
#                -L {input.acgt_ivals} \
#                -O {params.doc_base} \
#                --omit-depth-output-at-each-base \
#                --omit-locus-table \
#                --omit-interval-statistics \
#                --tmp-dir {params.tmp_dir}
#        '''

rule bqsr_analyze_covariates:
    input:
        bqsr_before = "{bucket}/wgs/{breed}/{sample_name}/{ref}/logs/{sample_name}.{ref}.recal_data.txt",
        bqsr_after  = "{bucket}/wgs/{breed}/{sample_name}/{ref}/logs/{sample_name}.{ref}.second_recal_data.txt",
    output:
        ac_pdf = S3.remote("{bucket}/wgs/{breed}/{sample_name}/{ref}/qc/{sample_name}.{ref}.analyze_cov.pdf"),
        ac_csv = S3.remote("{bucket}/wgs/{breed}/{sample_name}/{ref}/qc/{sample_name}.{ref}.analyze_cov.csv"),
    benchmark:
        "{bucket}/wgs/{breed}/{sample_name}/{ref}/qc/{sample_name}.bqsr_analyze_cov.benchmark.txt"
    resources:
         time   = 10,
         mem_mb = 4000
    shell:
        '''
            gatk AnalyzeCovariates \
                -before {input.bqsr_before} \
                -after {input.bqsr_after} \
                -plots {output.ac_pdf} \
                -csv {output.ac_csv}
        '''

rule qualimap_bamqc:
    input:
        final_bam = S3.remote("{bucket}/wgs/{breed}/{sample_name}/{ref}/bam/{sample_name}.{ref}.bam"),
        final_bai = S3.remote("{bucket}/wgs/{breed}/{sample_name}/{ref}/bam/{sample_name}.{ref}.bai"),
    output:
        report_pdf  = "{bucket}/wgs/{breed}/{sample_name}/{ref}/qc/qualimap/report.pdf",
        report_html = "{bucket}/wgs/{breed}/{sample_name}/{ref}/qc/qualimap/qualimapReport.html",
        report_txt  = S3.remote("{bucket}/wgs/{breed}/{sample_name}/{ref}/qc/qualimap/genome_results.txt"),
        raw_dat     = directory("{bucket}/wgs/{breed}/{sample_name}/{ref}/qc/qualimap/raw_data_qualimapReport/"),
        figures     = directory("{bucket}/wgs/{breed}/{sample_name}/{ref}/qc/qualimap/images_qualimapReport/"),
        css         = directory("{bucket}/wgs/{breed}/{sample_name}/{ref}/qc/qualimap/css/"),
    params:
        out_dir = "{bucket}/wgs/{breed}/{sample_name}/{ref}/qc/qualimap/",
    benchmark:
        "{bucket}/wgs/{breed}/{sample_name}/{ref}/qc/qualimap/{sample_name}.multimap_bamqc.benchmark.txt"
    threads: 12
    resources:
         time   = 120,
         mem_mb = 24000
    shell:
        '''
            qualimap bamqc \
                -bam {input.final_bam} \
                -outdir {params.out_dir} \
                -outformat PDF:HTML \
                -nt 12 \
                --java-mem-size=24G
        '''

rule multiqc:
    input:
        r1_zip      = S3.remote(
            expand(
                "{{bucket}}/wgs/{{breed}}/{{sample_name}}/fastqc/{{sample_name}}/{u.flowcell}/{u.readgroup_name}_R1_fastqc.zip",
                u=units.itertuples()
            )
        ),
        r2_zip      = S3.remote(
            expand(
                "{{bucket}}/wgs/{{breed}}/{{sample_name}}/fastqc/{{sample_name}}/{u.flowcell}/{u.readgroup_name}_R2_fastqc.zip",
                u=units.itertuples()
            )
        ),
        flagstat    = S3.remote("{bucket}/wgs/{breed}/{sample_name}/{ref}/qc/{sample_name}.{ref}.flagstat.txt"),
        bqsr_before = "{bucket}/wgs/{breed}/{sample_name}/{ref}/logs/{sample_name}.{ref}.recal_data.txt",
        bqsr_after  = "{bucket}/wgs/{breed}/{sample_name}/{ref}/logs/{sample_name}.{ref}.second_recal_data.txt",
        ac_csv      = S3.remote("{bucket}/wgs/{breed}/{sample_name}/{ref}/qc/{sample_name}.{ref}.analyze_cov.csv"),
        metrics     = expand(
            "{{bucket}}/wgs/{{breed}}/{{sample_name}}/{{ref}}/bam/{u.readgroup_name}.mark_adapt.metrics.txt",
            u=units.itertuples()
        ),
        report_txt  = S3.remote("{bucket}/wgs/{breed}/{sample_name}/{ref}/qc/qualimap/genome_results.txt"),
        raw_dat     = rules.qualimap_bamqc.output.raw_dat,
    output: 
        S3.remote("{bucket}/wgs/{breed}/{sample_name}/{ref}/qc/multiqc_report.html"),
        mqc_log    = S3.remote("{bucket}/wgs/{breed}/{sample_name}/{ref}/qc/multiqc_report_data/multiqc.log"),
        mqc_bamqc  = S3.remote("{bucket}/wgs/{breed}/{sample_name}/{ref}/qc/multiqc_report_data/multiqc_qualimap_bamqc_genome_results.txt"),
        mqc_dups   = S3.remote("{bucket}/wgs/{breed}/{sample_name}/{ref}/qc/multiqc_report_data/multiqc_picard_dups.txt"),
        mqc_adapt  = S3.remote("{bucket}/wgs/{breed}/{sample_name}/{ref}/qc/multiqc_report_data/multiqc_picard_mark_illumina_adapters.txt"),
        mqc_flag   = S3.remote("{bucket}/wgs/{breed}/{sample_name}/{ref}/qc/multiqc_report_data/multiqc_samtools_flagstat.txt"),
        mqc_fastqc = S3.remote("{bucket}/wgs/{breed}/{sample_name}/{ref}/qc/multiqc_report_data/multiqc_fastqc.txt"),
        mqc_gen    = S3.remote("{bucket}/wgs/{breed}/{sample_name}/{ref}/qc/multiqc_report_data/multiqc_general_stats.txt"),
        mqc_src    = S3.remote("{bucket}/wgs/{breed}/{sample_name}/{ref}/qc/multiqc_report_data/multiqc_sources.txt"),
        mqc_json   = S3.remote("{bucket}/wgs/{breed}/{sample_name}/{ref}/qc/multiqc_report_data/multiqc_data.json"),
       #qc_dat   = directory("{bucket}/wgs/{breed}/{sample_name}/{ref}/qc/multiqc_report_data/"),
       #qc_plots = directory("{bucket}/wgs/{breed}/{sample_name}/{ref}/qc/multiqc_report_plots/")
    params:
        "-x '*duplicates_marked*' -x '*group_*' -e snippy"
    wrapper: 
       "master/bio/multiqc"

