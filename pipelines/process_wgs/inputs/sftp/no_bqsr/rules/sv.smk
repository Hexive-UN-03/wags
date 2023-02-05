
# no longer tracking left aligned versus not here - could rethink...
rule split_bam:
    input:
        final_bam = "{bucket}/wgs/{breed}/{sample_name}/{ref}/bam/{sample_name}.{ref}.bam"
            if not config['left_align'] else "{bucket}/wgs/{breed}/{sample_name}/{ref}/bam/{sample_name}.{ref}.left_aligned.bam",
        final_bai = "{bucket}/wgs/{breed}/{sample_name}/{ref}/bam/{sample_name}.{ref}.bai"
            if not config['left_align'] else "{bucket}/wgs/{breed}/{sample_name}/{ref}/bam/{sample_name}.{ref}.left_aligned.bai",
        bed       = "{bucket}/bed_group/{bed}.bed"
    output:
        split_bam = temp("{bucket}/wgs/{breed}/{sample_name}/{ref}/svar/lumpy/{bed}/{sample_name}.{bed}.bam"),
        split_bai = temp("{bucket}/wgs/{breed}/{sample_name}/{ref}/svar/lumpy/{bed}/{sample_name}.{bed}.bam.bai")
    threads: 12
    resources:
         time   = 120,
         mem_mb = 24000
    shell:
        '''
            set -e

            samtools view \
                -@ {threads} \
                -L {input.bed} \
                -b \
                -o {output.split_bam} \
                {input.final_bam}

            samtools index -@ {threads} -b {output.split_bam}
        '''

rule sv_delly_split:
    input:
        split_bam = "{bucket}/wgs/{breed}/{sample_name}/{ref}/svar/lumpy/{bed}/{sample_name}.{bed}.bam",
        split_bai = "{bucket}/wgs/{breed}/{sample_name}/{ref}/svar/lumpy/{bed}/{sample_name}.{bed}.bam.bai"
    output:
        delly_tmp = "{bucket}/wgs/{breed}/{sample_name}/{ref}/svar/delly/{bed}/{sample_name}.delly.{bed}.tmp.bcf",
    params:
        conda_env = config['conda_envs']['delly'],
        ref_fasta = config['ref_fasta'],
    benchmark:
        "{bucket}/wgs/{breed}/{sample_name}/{ref}/svar/delly/{bed}/{sample_name}.delly.{bed}.benchmark.txt"
    threads: 12
    resources:
         time   = 720,
         mem_mb = 60000
    shell:
        '''
            source activate {params.conda_env}

            export OMP_NUM_THREADS={threads}

            # call svs for each sv type
            delly call \
                -t ALL \
                -g {params.ref_fasta} \
                -o {output.delly_tmp} \
                {input.split_bam}
        '''

rule sv_delly_filter:
    input:
        delly_tmp = "{bucket}/wgs/{breed}/{sample_name}/{ref}/svar/delly/{bed}/{sample_name}.delly.{bed}.tmp.bcf",
    output:
        sv_bcf = "{bucket}/wgs/{breed}/{sample_name}/{ref}/svar/delly/{bed}/{sample_name}.{ref}.bcf.gz",
        sv_csi = "{bucket}/wgs/{breed}/{sample_name}/{ref}/svar/delly/{bed}/{sample_name}.{ref}.bcf.gz.csi"
    benchmark:
        "{bucket}/wgs/{breed}/{sample_name}/{ref}/svar/delly/{bed}/{sample_name}.delly.{bed}.filter.benchmark.txt"
    threads: 12
    resources:
         time   = 720,
         mem_mb = 60000
    shell:
        '''
            # filter for pass and save as compressed bcf
            bcftools filter \
                -O b \
                -o {output.sv_bcf} \
                -i "FILTER == 'PASS'" \
                {input.delly_tmp}

            # index filtered output
            bcftools index {output.sv_bcf}
        '''

rule sv_delly_concat:
    input:
        sorted(expand(
            "{bucket}/wgs/{breed}/{sample_name}/{ref}/svar/delly/{bed}/{sample_name}.{ref}.bcf.gz",
            bucket=config['bucket'],
            breed=breed,
            sample_name=sample_name,
            ref=config['ref'],
            bed=beds
        ))
    output:
        sv_gz  = STFP.remote("{bucket}/wgs/{breed}/{sample_name}/{ref}/svar/delly/{sample_name}.delly.{ref}.vcf.gz"),
        sv_tbi = STFP.remote("{bucket}/wgs/{breed}/{sample_name}/{ref}/svar/delly/{sample_name}.delly.{ref}.vcf.gz.tbi")
    params:
        vcf_tmp = "{bucket}/wgs/{breed}/{sample_name}/{ref}/svar/delly/{sample_name}.delly.{ref}.tmp.vcf",
    benchmark:
        "{bucket}/wgs/{breed}/{sample_name}/{ref}/svar/delly/{sample_name}.delly_concat.benchmark.txt"
    threads: 12
    resources:
         time   = 480,
         mem_mb = 60000
    shell:
        '''
            set -e

            bcftools concat \
                -a \
                -O v \
                -o {params.vcf_tmp} \
                {input}

            # bgzip and index
            bgzip --threads {threads} -c {params.vcf_tmp} > {output.sv_gz}
            tabix -p vcf {output.sv_gz}

            rm -f {params.vcf_tmp}
        '''

rule sv_gridss:
    input:
        final_bam = "{bucket}/wgs/{breed}/{sample_name}/{ref}/bam/{sample_name}.{ref}.bam"
            if not config['left_align'] else "{bucket}/wgs/{breed}/{sample_name}/{ref}/bam/{sample_name}.{ref}.left_aligned.bam",
        final_bai = "{bucket}/wgs/{breed}/{sample_name}/{ref}/bam/{sample_name}.{ref}.bai"
            if not config['left_align'] else "{bucket}/wgs/{breed}/{sample_name}/{ref}/bam/{sample_name}.{ref}.left_aligned.bai",
    output:
        gridss_bam = STFP.remote("{bucket}/wgs/{breed}/{sample_name}/{ref}/svar/gridss/{sample_name}.gridss.{ref}.bam"),
        sv_gz      = STFP.remote("{bucket}/wgs/{breed}/{sample_name}/{ref}/svar/gridss/{sample_name}.gridss.{ref}.vcf.gz"),
        sv_tbi     = STFP.remote("{bucket}/wgs/{breed}/{sample_name}/{ref}/svar/gridss/{sample_name}.gridss.{ref}.vcf.gz.tbi")
    params:
        gridss_tmp  = "{bucket}/wgs/{breed}/{sample_name}/{ref}/svar/gridss/{sample_name}.gridss.{ref}.tmp.vcf",
        gridss_filt = "{bucket}/wgs/{breed}/{sample_name}/{ref}/svar/gridss/{sample_name}.gridss.{ref}.tmp.filt.vcf",
        work_dir    = lambda wildcards, output: os.path.dirname(output.sv_gz),
        conda_env   = config['conda_envs']['gridss'],
        ref_fasta   = config['ref_fasta'],
    benchmark:
        "{bucket}/wgs/{breed}/{sample_name}/{ref}/svar/gridss/{sample_name}.sv_gridss.benchmark.txt"
    threads: 8
    resources:
         time   = 1440,
         mem_mb = 36000
    shell:
        '''
            source activate {params.conda_env}

            gridss \
                -t 8 \
                -r {params.ref_fasta} \
                -o {params.gridss_tmp} \
                -a {output.gridss_bam} \
                --jvmheap 32g \
                -w {params.work_dir} \
                {input.final_bam} \

            # removed -i "FILTER == '.'" as no records were returned
            # unclear if issue sample or larger...
            # filter for pass and save as uncompressed vcf
            bcftools filter \
                -O v \
                -o {params.gridss_filt} \
                {params.gridss_tmp}
            
            # bgzip and index
            bgzip --threads {threads} -c {params.gridss_filt} > {output.sv_gz}
            tabix -p vcf {output.sv_gz}
        '''

rule sv_lumpy_split:
    input:
        split_bam = "{bucket}/wgs/{breed}/{sample_name}/{ref}/svar/lumpy/{bed}/{sample_name}.{bed}.bam",
        split_bai = "{bucket}/wgs/{breed}/{sample_name}/{ref}/svar/lumpy/{bed}/{sample_name}.{bed}.bam.bai"
    output:
        lumpy_tmp  = "{bucket}/wgs/{breed}/{sample_name}/{ref}/svar/lumpy/{bed}/{sample_name}.lumpy.{ref}.tmp.vcf",
    params:
        work_dir   = lambda wildcards, output: os.path.join(os.path.dirname(output.lumpy_tmp), ".temp"),
        conda_env  = config['conda_envs']['lumpy'],
    benchmark:
        "{bucket}/wgs/{breed}/{sample_name}/{ref}/svar/lumpy/{bed}/{sample_name}.sv_lumpy.benchmark.txt"
    threads: 8
    resources:
         time   = 2880,
         mem_mb = 60000
    shell:
        '''
            set -e
            source activate {params.conda_env}

            lumpyexpress \
                -B {input.split_bam} \
                -o {output.lumpy_tmp} \
                -T {params.work_dir}
        '''

rule sv_lumpy_filter:
    input:
        lumpy_tmp = "{bucket}/wgs/{breed}/{sample_name}/{ref}/svar/lumpy/{bed}/{sample_name}.lumpy.{ref}.tmp.vcf",
    output:
        sv_gz  = "{bucket}/wgs/{breed}/{sample_name}/{ref}/svar/lumpy/{bed}/{sample_name}.lumpy.{ref}.vcf.gz",
        sv_tbi = "{bucket}/wgs/{breed}/{sample_name}/{ref}/svar/lumpy/{bed}/{sample_name}.lumpy.{ref}.vcf.gz.tbi"
    params:
        lumpy_filt = "{bucket}/wgs/{breed}/{sample_name}/{ref}/svar/lumpy/{bed}/{sample_name}.lumpy.{ref}.filt.tmp.vcf",
        lumpy_sort = "{bucket}/wgs/{breed}/{sample_name}/{ref}/svar/lumpy/{bed}/{sample_name}.lumpy.{ref}.sort.filt.tmp.vcf",
        ref_fasta  = config['ref_fasta'],
        ref_dict   = config['ref_dict']
    benchmark:
        "{bucket}/wgs/{breed}/{sample_name}/{ref}/svar/lumpy/{bed}/{sample_name}.sv_lumpy.filter.benchmark.txt"
    threads: 8
    resources:
         time   = 2880,
         mem_mb = 60000
    shell:
        '''
            set -e

            # filter for pass and save as uncompressed vcf
            bcftools filter \
                -O v \
                -o {params.lumpy_filt} \
                -i "FILTER == '.'" \
                {input.lumpy_tmp}
           
            # sort using ref dict
            gatk SortVcf \
                -SD {params.ref_dict} \
                -I {params.lumpy_filt} \
                -O {params.lumpy_sort}

            # bgzip and index
            bgzip --threads {threads} -c {params.lumpy_sort} > {output.sv_gz}
            tabix -p vcf {output.sv_gz}
        '''

rule sv_lumpy_concat:
    input:
        sorted(expand(
            "{bucket}/wgs/{breed}/{sample_name}/{ref}/svar/lumpy/{bed}/{sample_name}.lumpy.{ref}.vcf.gz",
            bucket=config['bucket'],
            breed=breed,
            sample_name=sample_name,
            ref=config['ref'],
            bed=beds
        )),
    output:
        sv_gz  = STFP.remote("{bucket}/wgs/{breed}/{sample_name}/{ref}/svar/lumpy/{sample_name}.lumpy.{ref}.vcf.gz"),
        sv_tbi = STFP.remote("{bucket}/wgs/{breed}/{sample_name}/{ref}/svar/lumpy/{sample_name}.lumpy.{ref}.vcf.gz.tbi")
    params:
        vcf_tmp = "{bucket}/wgs/{breed}/{sample_name}/{ref}/svar/lumpy/{sample_name}.lumpy.{ref}.tmp.vcf.gz",
        svs     = lambda wildcards, input: " --input ".join(map(str,input)),
    benchmark:
        "{bucket}/wgs/{breed}/{sample_name}/{ref}/svar/lumpy/{sample_name}.lumpy_concat.benchmark.txt"
    threads: 12
    resources:
         time   = 600,
         mem_mb = 24000
    shell:
        '''
            set -e

            gatk --java-options "-Xmx18g -Xms6g" \
                GatherVcfsCloud \
                --ignore-safety-checks \
                --gather-type BLOCK \
                --input {params.svs} \
                --output {params.vcf_tmp}

            zcat {params.vcf_tmp} | bgzip --threads {threads} -c > {output.sv_gz} &&
            tabix -p vcf {output.sv_gz}

            rm -f {params.vcf_tmp}
        '''

rule sv_manta:
    input:
        final_bam = "{bucket}/wgs/{breed}/{sample_name}/{ref}/bam/{sample_name}.{ref}.bam"
            if not config['left_align'] else "{bucket}/wgs/{breed}/{sample_name}/{ref}/bam/{sample_name}.{ref}.left_aligned.bam",
        final_bai = "{bucket}/wgs/{breed}/{sample_name}/{ref}/bam/{sample_name}.{ref}.bai"
            if not config['left_align'] else "{bucket}/wgs/{breed}/{sample_name}/{ref}/bam/{sample_name}.{ref}.left_aligned.bai",
    output:
        sv_gz      = STFP.remote("{bucket}/wgs/{breed}/{sample_name}/{ref}/svar/manta/{sample_name}.manta.diploidSV.{ref}.vcf.gz"),
        sv_tbi     = STFP.remote("{bucket}/wgs/{breed}/{sample_name}/{ref}/svar/manta/{sample_name}.manta.diploidSV.{ref}.vcf.gz.tbi"),
        cand_stat  = STFP.remote("{bucket}/wgs/{breed}/{sample_name}/{ref}/svar/manta/results/stats/svCandidateGenerationStats.tsv"),
        graph_stat = STFP.remote("{bucket}/wgs/{breed}/{sample_name}/{ref}/svar/manta/results/stats/svLocusGraphStats.tsv"),
        align_stat = STFP.remote("{bucket}/wgs/{breed}/{sample_name}/{ref}/svar/manta/results/stats/alignmentStatsSummary.txt"),
    params:
        manta_tmp  = "{bucket}/wgs/{breed}/{sample_name}/{ref}/svar/manta/results/variants/diploidSV.vcf.gz",
        manta_filt = "{bucket}/wgs/{breed}/{sample_name}/{ref}/svar/manta/results/variants/diploidSV.filt.vcf",
        work_dir    = lambda wildcards, output: os.path.dirname(output.sv_gz),
        conda_env   = config['conda_envs']['manta'],
        ref_fasta   = config['ref_fasta'],
    benchmark:
        "{bucket}/wgs/{breed}/{sample_name}/{ref}/svar/manta/{sample_name}.manta.benchmark.txt"
    threads: 24
    resources:
         time   = 1440,
         mem_mb = 36000
    shell:
        '''
            source activate {params.conda_env}

            configManta.py \
                --bam {input.final_bam} \
                --reference {params.ref_fasta} \
                --runDir {params.work_dir}
           
            # cd to working dir
            cd {params.work_dir}

            ./runWorkflow.py \
                --quiet \
                -m local \
                -j {threads}

            # cd back to working dir
            cd -

            # filter for pass and save as uncompressed vcf
            bcftools filter \
                -O v \
                -o {params.manta_filt} \
                -i "FILTER == 'PASS'" \
                {params.manta_tmp}
            
            # bgzip and index
            bgzip --threads {threads} -c {params.manta_filt} > {output.sv_gz}
            tabix -p vcf {output.sv_gz}
        '''

rule sv_done:
    input:
        STFP.remote("{bucket}/wgs/{breed}/{sample_name}/{ref}/svar/delly/{sample_name}.delly.{ref}.vcf.gz"),
        STFP.remote("{bucket}/wgs/{breed}/{sample_name}/{ref}/svar/delly/{sample_name}.delly.{ref}.vcf.gz.tbi"),
        STFP.remote("{bucket}/wgs/{breed}/{sample_name}/{ref}/svar/gridss/{sample_name}.gridss.{ref}.vcf.gz"),
        STFP.remote("{bucket}/wgs/{breed}/{sample_name}/{ref}/svar/gridss/{sample_name}.gridss.{ref}.vcf.gz.tbi"),
        STFP.remote("{bucket}/wgs/{breed}/{sample_name}/{ref}/svar/lumpy/{sample_name}.lumpy.{ref}.vcf.gz"),
        STFP.remote("{bucket}/wgs/{breed}/{sample_name}/{ref}/svar/lumpy/{sample_name}.lumpy.{ref}.vcf.gz.tbi"),
        STFP.remote("{bucket}/wgs/{breed}/{sample_name}/{ref}/svar/manta/{sample_name}.manta.diploidSV.{ref}.vcf.gz"),
        STFP.remote("{bucket}/wgs/{breed}/{sample_name}/{ref}/svar/manta/{sample_name}.manta.diploidSV.{ref}.vcf.gz.tbi"),
        STFP.remote("{bucket}/wgs/{breed}/{sample_name}/{ref}/svar/manta/results/stats/svCandidateGenerationStats.tsv"),
        STFP.remote("{bucket}/wgs/{breed}/{sample_name}/{ref}/svar/manta/results/stats/svLocusGraphStats.tsv"),
        STFP.remote("{bucket}/wgs/{breed}/{sample_name}/{ref}/svar/manta/results/stats/alignmentStatsSummary.txt"),
    output:
        touch("{bucket}/wgs/{breed}/{sample_name}/{ref}/svar/sv.done")

