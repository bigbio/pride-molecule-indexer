#!/usr/bin/env nextflow
/*
========================================================================================
                         nf-core/proteomicslfq
========================================================================================
 nf-core/proteomicslfq Analysis Pipeline.
 #### Homepage / Documentation
 https://github.com/nf-core/proteomicslfq
----------------------------------------------------------------------------------------
*/

def helpMessage() {
    log.info nfcoreHeader()
    log.info"""

    Usage:

    The typical command for running the pipeline is as follows:

    nextflow run bigbio/pride-molecules-indexer --project_accession "PXD029360" -profile conda

    Main arguments:
      --project_accession           Project accession to convert the identifications to json files.
      --outdir                      Output directory containing the information (json) of the project

      Advanced Options:
      --pride_production_folder     (Optional) Local folder that contains the submitted files for PRIDE

    Other options:
      --outdir [file]                 The output directory where the results will be saved
      --publish_dir_mode [str]        Mode for publishing results in the output directory. Available: symlink, rellink, link, copy, copyNoFollow, move (Default: copy)
      --email [email]                 Set this parameter to your e-mail address to get a summary e-mail with details of the run sent to you when the workflow exits
      --email_on_fail [email]         Same as --email, except only send mail if the workflow is not successful
      -name [str]                     Name for the pipeline run. If not specified, Nextflow will automatically generate a random mnemonic

    """.stripIndent()
}

// Show help message
if (params.help) {
    helpMessage()
    exit 0
}

/*
 * SET UP CONFIGURATION VARIABLES
 */

// Has the run name been specified by the user?
// this has the bonus effect of catching both -name and --name
custom_runName = params.name
if (!(workflow.runName ==~ /[a-z]+_[a-z]+/)) {
    custom_runName = workflow.runName
}

// Stage config files
ch_output_docs = file("$baseDir/docs/output.md", checkIfExists: true)
ch_output_docs_images = file("$baseDir/docs/images/", checkIfExists: true)

// Validate input
if (isCollectionOrArray(params.project_accession)){
  tocheck = params.project_accession[0]
} else {
  tocheck = params.project_accession
}

params.project_accession = params.project_accession ?: { log.error "No project accession provided. Make sure you have used the '--project_accession' option."; exit 1 }()
params.outdir = params.outdir ?: { log.warn "No output directory provided. Will put the results into './results'"; return "./results" }()

process project_get_result_files{

  publishDir "${params.outdir}/result_files", mode: 'copy', pattern: '*.tsv'

  input:

  output:
   file "*.tsv" into result_file_summary

  script:
  """
  java -jar ${projectDir}/bin/pride-molecules-indexer-1.0.0-SNAPSHOT.jar get-result-files --app.project-accession=${params.project_accession} \
       --app.file-output=${params.project_accession}-result_files.tsv
  """
}

result_file_summary.splitCsv(skip: 1, sep: '\t')
  .multiMap{ row -> id = row[0]
                    result_files: tuple(id, !params.root_folder ? row[3].replace("ftp://", "http://") :params.root_folder + "/" + row[0])
           }
  .set{ch_result_files}

//ch_result_files.subscribe { println "value: $it" }

process uncompress_result_files{

   label 'downloading_thread'

   input:
     tuple result_id, result_file_path from ch_result_files.result_files

   output:
     tuple result_id, file("*") into ch_result_uncompress

   script:
   """
   wget ${result_file_path}
   gunzip ${result_id}
   """
}

process project_get_related_spectra{

publishDir "${params.outdir}/result_files", mode: 'copy', pattern: '*.tsv'

  input:
    tuple result_id, file(uncompress_result) from ch_result_uncompress

  output:
    tuple result_id, file("*.tsv") into ch_spectra_summary

  script:
  """
  java -jar ${projectDir}/bin/pride-molecules-indexer-1.0.0-SNAPSHOT.jar get-related-files --app.project-accession=${params.project_accession} \
       --app.file-output=${params.project_accession}-${result_id}-result_spectra.tsv --app.result-file=${uncompress_result}
  """
}

/*
 * Create a channel for input files
 */

 //Filename        FixedModifications      VariableModifications   Label   PrecursorMassTolerance  PrecursorMassToleranceUnit      FragmentMassTolerance   DissociationMethod      Enzyme


// if (!sdrf_file)
// {
//   ch_spectra = Channel.fromPath(spectra_files, checkIfExists: true)
//   ch_spectra
//   .multiMap{ it -> id = it.toString().md5()
//                     comet_settings: msgf_settings: tuple(id,
//                                     params.fixed_mods,
//                                     params.variable_mods,
//                                     "", //labelling modifications currently not supported
//                                     params.precursor_mass_tolerance,
//                                     params.precursor_mass_tolerance_unit,
//                                     params.fragment_mass_tolerance,
//                                     params.fragment_mass_tolerance_unit,
//                                     params.fragment_method,
//                                     params.enzyme)
//                     idx_settings: tuple(id,
//                                     params.enzyme)
//                     luciphor_settings:
//                                   tuple(id,
//                                     params.fragment_method)
//                     mzmls: tuple(id,it)}
//   .set{ch_sdrf_config}
// }
// else
// {
//   ch_sdrf = Channel.fromPath(sdrf_file, checkIfExists: true)
//   /*
//    * STEP 0 - SDRF parsing
//    */
//   process sdrf_parsing {
//
//       publishDir "${params.outdir}/logs", mode: 'copy', pattern: '*.log'
//
//       input:
//        file sdrf from ch_sdrf
//
//       output:
//        file "experimental_design.tsv" into ch_expdesign
//        file "openms.tsv" into ch_sdrf_config_file
//
//       when:
//         sdrf_file
//
//       script:
//        """
//        ## -t2 since the one-table format parser is broken in OpenMS2.5
//        ## -l for legacy behavior to always add sample columns
//        parse_sdrf convert-openms -t2 -l -s ${sdrf} > sdrf_parsing.log
//        """
//   }
//
//   //TODO use header and reference by col name instead of index
//   ch_sdrf_config_file
//   .splitCsv(skip: 1, sep: '\t')
//   .multiMap{ row -> id = row.toString().md5()
//                     comet_settings: msgf_settings: tuple(id,
//                                     row[2],
//                                     row[3],
//                                     row[4],
//                                     row[5],
//                                     row[6],
//                                     row[7],
//                                     row[8],
//                                     row[9],
//                                     row[10])
//                     idx_settings: tuple(id,
//                                     row[10])
//                     luciphor_settings:
//                                   tuple(id,
//                                     row[9])
//                     mzmls: tuple(id, !params.root_folder ?
//                                     row[0] :
//                                     params.root_folder + "/" + (params.local_input_type ?
//                                         row[1].take(row[1].lastIndexOf('.')) + '.' + params.local_input_type :
//                                         row[1]))}
//   .set{ch_sdrf_config}
// }

// ch_db_for_decoy_creation = Channel.fromPath(params.database)
//
// // overwrite experimental design if given additionally to SDRF
// //TODO think about that
// if (params.expdesign)
// {
//     Channel
//         .fromPath(params.expdesign)
//         .set { ch_expdesign }
// }
//
// ch_sdrf_config.mzmls
// .branch {
//         raw: hasExtension(it[1], 'raw')
//         mzML: hasExtension(it[1], 'mzML')
// }
// .set {branched_input}
//
//
// //TODO we could also check for outdated mzML versions and try to update them
// branched_input.mzML
// .branch {
//     nonIndexedMzML: file(it[1]).withReader {
//                         f = it;
//                         1.upto(5) {
//                             if (f.readLine().contains("indexedmzML")) return false;
//                         }
//                         return true;
//                     }
//     inputIndexedMzML: file(it[1]).withReader {
//                         f = it;
//                         1.upto(5) {
//                             if (f.readLine().contains("indexedmzML")) return true;
//                         }
//                         return false;
//                     }
// }
// .set {branched_input_mzMLs}
//
// //Push raw files through process that does the conversion, everything else directly to downstream Channel with mzMLs
//
// //This piece only runs on data that is a.) raw and b.) needs conversion
// //mzML files will be mixed after this step to provide output for downstream processing - allowing you to even specify mzMLs and RAW files in a mixed mode as input :-)
//
// /*
//  * STEP 0.1 - Raw file conversion
//  */
// process raw_file_conversion {
//
//     label 'process_low'
//     label 'process_single_thread'
//
//     publishDir "${params.outdir}/logs", mode: 'copy', pattern: '*.log'
//
//     input:
//      tuple mzml_id, path(rawfile) from branched_input.raw
//
//     output:
//      tuple mzml_id, file("*.mzML") into mzmls_converted
//
//     script:
//      """
//      ThermoRawFileParser.sh -i=${rawfile} -f=2 -o=./ > ${rawfile}_conversion.log
//      """
// }
//
// /*
//  * STEP 0.2 - MzML indexing
//  */
// process mzml_indexing {
//
//     label 'process_low'
//
//     publishDir "${params.outdir}/logs", mode: 'copy', pattern: '*.log'
//
//     input:
//      tuple mzml_id, path(mzmlfile) from branched_input_mzMLs.nonIndexedMzML
//
//     output:
//      tuple mzml_id, file("out/*.mzML") into mzmls_indexed
//      file "*.log"
//
//     script:
//      """
//      mkdir out
//      FileConverter -in ${mzmlfile} -out out/${mzmlfile.baseName}.mzML > ${mzmlfile.baseName}_mzmlindexing.log
//      """
// }
//
// //Mix the converted raw data with the already supplied mzMLs and push these to the same channels as before
//
// if (params.openms_peakpicking)
// {
//   branched_input_mzMLs.inputIndexedMzML.mix(mzmls_converted).mix(mzmls_indexed).set{mzmls_pp}
//   (mzmls_comet, mzmls_msgf, mzmls_luciphor, mzmls_plfq) = [Channel.empty(), Channel.empty(), Channel.empty(), Channel.empty()]
// }
// else
// {
//   branched_input_mzMLs.inputIndexedMzML.mix(mzmls_converted).mix(mzmls_indexed).into{mzmls_comet; mzmls_msgf; mzmls_luciphor; mzmls_plfq}
//   mzmls_pp = Channel.empty()
// }
//
// //Fill the channels with empty Channels in case that we want to add decoys. Otherwise fill with output from database.
// (searchengine_in_db_msgf, searchengine_in_db_comet, pepidx_in_db, plfq_in_db) = ( params.add_decoys
//                     ? [ Channel.empty(), Channel.empty(), Channel.empty(), Channel.empty() ]
//                     : [ Channel.fromPath(params.database), Channel.fromPath(params.database), Channel.fromPath(params.database), Channel.fromPath(params.database) ] )
//
// //Add decoys if params.add_decoys is set appropriately
// process generate_decoy_database {
//
//     label 'process_very_low'
//     label 'process_single_thread'
//
//     publishDir "${params.outdir}/logs", mode: 'copy', pattern: '*.log'
//
//     input:
//      file(mydatabase) from ch_db_for_decoy_creation
//
//     output:
//      file "${mydatabase.baseName}_decoy.fasta" into searchengine_in_db_decoy_msgf, searchengine_in_db_decoy_comet, pepidx_in_db_decoy, plfq_in_db_decoy
//      file "*.log"
//
//     when:
//      params.add_decoys
//
//     script:
//      """
//      DecoyDatabase  -in ${mydatabase} \\
//                  -out ${mydatabase.baseName}_decoy.fasta \\
//                  -decoy_string ${params.decoy_affix} \\
//                  -decoy_string_position ${params.affix_type} \\
//                  > ${mydatabase.baseName}_decoy_database.log
//      """
// }
//
// // Doesnt work yet. Maybe point the script to the workspace?
// // All the files should be there after collecting.
// //process generate_simple_exp_design_file {
// //    publishDir "${params.outdir}", mode: 'copy'
// //    input:
// //      val mymzmls from mzmls.collect()
//
// //    output:
// //        file "expdesign.tsv" into expdesign
// //    when:
// //        !params.expdesign
//
// //    script:
// //     strng = new File(mymzmls[0].toString()).getParentFile()
// //     """
// //       create_trivial_design.py ${strng} 1 > expdesign.tsv
// //     """
// //}
//
// process openms_peakpicker {
//
//     label 'process_low'
//
//     publishDir "${params.outdir}/logs", mode: 'copy', pattern: '*.log'
//
//     input:
//      tuple mzml_id, path(mzml_file) from mzmls_pp
//
//     when:
//       params.openms_peakpicking
//
//     output:
//      tuple mzml_id, file("out/${mzml_file.baseName}.mzML") into mzmls_comet_picked, mzmls_msgf_picked, mzmls_plfq_picked
//      file "*.log"
//
//     script:
//      in_mem = params.peakpicking_inmemory ? "inmemory" : "lowmemory"
//      lvls = params.peakpicking_ms_levels ? "-algorithm:ms_levels ${params.peakpicking_ms_levels}" : ""
//      """
//      mkdir out
//      PeakPickerHiRes -in ${mzml_file} \\
//                      -out out/${mzml_file.baseName}.mzML \\
//                      -threads ${task.cpus} \\
//                      -debug ${params.pp_debug} \\
//                      -processOption ${in_mem} \\
//                      ${lvls} \\
//                      > ${mzml_file.baseName}_pp.log
//      """
// }
//
// if (params.enzyme == "unspecific cleavage")
// {
//   params.num_enzyme_termini == "none"
// }
//
// pepidx_num_enzyme_termini = params.num_enzyme_termini
// if (params.num_enzyme_termini == "fully")
// {
//   pepidx_num_enzyme_termini = "full"
// }
//
// process search_engine_msgf {
//
//     label 'process_medium'
//
//     publishDir "${params.outdir}/logs", mode: 'copy', pattern: '*.log'
//
//     // ---------------------------------------------------------------------------------------------------------------------
//     // ------------- WARNING: If you experience nextflow running forever after a failure, set the following ----------------
//     // ---------------------------------------------------------------------------------------------------------------------
//     // This is probably true for other processes as well. See https://github.com/nextflow-io/nextflow/issues/1457
//     // errorStrategy 'terminate'
//
//     input:
//      tuple file(database), mzml_id, path(mzml_file), fixed, variable, label, prec_tol, prec_tol_unit, frag_tol, frag_tol_unit, diss_meth, enzyme from searchengine_in_db_msgf.mix(searchengine_in_db_decoy_msgf).combine(mzmls_msgf.mix(mzmls_msgf_picked).join(ch_sdrf_config.msgf_settings))
//
//      // This was another way of handling the combination
//      //file database from searchengine_in_db.mix(searchengine_in_db_decoy)
//      //each file(mzml_file) from mzmls
//     when:
//       params.search_engines.contains("msgf")
//
//     output:
//      tuple mzml_id, file("${mzml_file.baseName}_msgf.idXML") into id_files_msgf
//      file "*.log"
//
//     script:
//       if (enzyme == 'Trypsin') enzyme = 'Trypsin/P'
//       else if (enzyme == 'Arg-C') enzyme = 'Arg-C/P'
//       else if (enzyme == 'Asp-N') enzyme = 'Asp-N/B'
//       else if (enzyme == 'Chymotrypsin') enzyme = 'Chymotrypsin/P'
//       else if (enzyme == 'Lys-C') enzyme = 'Lys-C/P'
//
//       if ((frag_tol.toDouble() < 50 && frag_tol_unit == "ppm") || (frag_tol.toDouble() < 0.1 && frag_tol_unit == "Da"))
//       {
//         inst = params.instrument ?: "high_res"
//       } else {
//         inst = params.instrument ?: "low_res"
//       }
//      """
//      MSGFPlusAdapter -in ${mzml_file} \\
//                      -out ${mzml_file.baseName}_msgf.idXML \\
//                      -threads ${task.cpus} \\
//                      -java_memory ${task.memory.toMega()} \\
//                      -database "${database}" \\
//                      -instrument ${inst} \\
//                      -protocol "${params.protocol}" \\
//                      -matches_per_spec ${params.num_hits} \\
//                      -min_precursor_charge ${params.min_precursor_charge} \\
//                      -max_precursor_charge ${params.max_precursor_charge} \\
//                      -min_peptide_length ${params.min_peptide_length} \\
//                      -max_peptide_length ${params.max_peptide_length} \\
//                      -enzyme "${enzyme}" \\
//                      -tryptic ${params.num_enzyme_termini} \\
//                      -precursor_mass_tolerance ${prec_tol} \\
//                      -precursor_error_units ${prec_tol_unit} \\
//                      -fixed_modifications ${fixed.tokenize(',').collect { "'${it}'" }.join(" ") } \\
//                      -variable_modifications ${variable.tokenize(',').collect { "'${it}'" }.join(" ") } \\
//                      -max_mods ${params.max_mods} \\
//                      -debug ${params.db_debug} \\
//                      > ${mzml_file.baseName}_msgf.log
//      """
// }
//
// process search_engine_comet {
//
//     label 'process_medium'
//
//     publishDir "${params.outdir}/logs", mode: 'copy', pattern: '*.log'
//
//     // ---------------------------------------------------------------------------------------------------------------------
//     // ------------- WARNING: If you experience nextflow running forever after a failure, set the following ----------------
//     // ---------------------------------------------------------------------------------------------------------------------
//     // This is probably true for other processes as well. See https://github.com/nextflow-io/nextflow/issues/1457
//     //errorStrategy 'terminate'
//
//     input:
//      tuple file(database), mzml_id, path(mzml_file), fixed, variable, label, prec_tol, prec_tol_unit, frag_tol, frag_tol_unit, diss_meth, enzyme from searchengine_in_db_comet.mix(searchengine_in_db_decoy_comet).combine(mzmls_comet.mix(mzmls_comet_picked).join(ch_sdrf_config.comet_settings))
//
//     when:
//       params.search_engines.contains("comet")
//
//     output:
//      tuple mzml_id, file("${mzml_file.baseName}_comet.idXML") into id_files_comet
//      file "*.log"
//
//     //TODO we currently ignore the activation_method param to leave the default "ALL" for max. compatibility
//     //Note: OpenMS CometAdapter will double the number that is passed to fragment_mass_tolerance to "convert"
//     // it to a fragment_bin_tolerance
//     script:
//      if (frag_tol_unit == "ppm") {
//        // Note: This uses an arbitrary rule to decide if it was hi-res or low-res
//        // and uses Comet's defaults for bin size (i.e. by passing 0.5*default to the Adapter), in case unsupported unit "ppm" was given.
//        if (frag_tol.toDouble() < 50) {
//          bin_tol = 0.015
//          bin_offset = 0.0
//          inst = params.instrument ?: "high_res"
//        } else {
//          bin_tol = 0.50025
//          bin_offset = 0.4
//          inst = params.instrument ?: "low_res"
//        }
//        log.warn "The chosen search engine Comet does not support ppm fragment tolerances. We guessed a " + inst +
//          " instrument and set the fragment_bin_tolerance to " + bin_tol
//      } else {
//        //TODO expose the fragment_bin_offset parameter of comet
//        bin_tol = frag_tol.toDouble()
//        bin_offset = bin_tol <= 0.05 ? 0.0 : 0.4
//        if (!params.instrument)
//        {
//          inst = bin_tol <= 0.05 ? "high_res" : "low_res"
//        } else {
//          inst = params.instrument
//        }
//      }
//
//      // for consensusID the cutting rules need to be the same. So we adapt to the loosest rules from MSGF
//      // TODO find another solution. In ProteomicsLFQ we re-run PeptideIndexer (remove??) and if we
//      // e.g. add XTandem, after running ConsensusID it will lose the auto-detection ability for the
//      // XTandem specific rules.
//      if (params.search_engines.contains("msgf"))
//      {
//         if (enzyme == 'Trypsin') enzyme = 'Trypsin/P'
//         else if (enzyme == 'Arg-C') enzyme = 'Arg-C/P'
//         else if (enzyme == 'Asp-N') enzyme = 'Asp-N/B'
//         else if (enzyme == 'Chymotrypsin') enzyme = 'Chymotrypsin/P'
//         else if (enzyme == 'Lys-C') enzyme = 'Lys-C/P'
//      }
//      """
//      CometAdapter  -in ${mzml_file} \\
//                    -out ${mzml_file.baseName}_comet.idXML \\
//                    -threads ${task.cpus} \\
//                    -database "${database}" \\
//                    -instrument ${inst} \\
//                    -missed_cleavages ${params.allowed_missed_cleavages} \\
//                    -num_hits ${params.num_hits} \\
//                    -num_enzyme_termini ${params.num_enzyme_termini} \\
//                    -enzyme "${enzyme}" \\
//                    -precursor_charge ${params.min_precursor_charge}:${params.max_precursor_charge} \\
//                    -fixed_modifications ${fixed.tokenize(',').collect { "'${it}'" }.join(" ") } \\
//                    -variable_modifications ${variable.tokenize(',').collect { "'${it}'" }.join(" ") } \\
//                    -max_variable_mods_in_peptide ${params.max_mods} \\
//                    -precursor_mass_tolerance ${prec_tol} \\
//                    -precursor_error_units ${prec_tol_unit} \\
//                    -fragment_mass_tolerance ${bin_tol} \\
//                    -fragment_bin_offset ${bin_offset} \\
//                    -debug ${params.db_debug} \\
// 		   -force \\
//                    > ${mzml_file.baseName}_comet.log
//      """
// }
//
//
// process index_peptides {
//
//     label 'process_low'
//
//     publishDir "${params.outdir}/logs", mode: 'copy', pattern: '*.log'
//
//     input:
//      tuple mzml_id, file(id_file), val(enzyme), file(database) from id_files_msgf.mix(id_files_comet).combine(ch_sdrf_config.idx_settings, by: 0).combine(pepidx_in_db.mix(pepidx_in_db_decoy))
//
//     output:
//      tuple mzml_id, file("${id_file.baseName}_idx.idXML") into id_files_idx_ForPerc, id_files_idx_ForIDPEP, id_files_idx_ForIDPEP_noFDR
//      file "*.log"
//
//     script:
//      def il = params.IL_equivalent ? '-IL_equivalent' : ''
//      def allow_um = params.allow_unmatched ? '-allow_unmatched' : ''
//      // see comment in CometAdapter. Alternative here in PeptideIndexer is to let it auto-detect the enzyme by not specifying.
//      if (params.search_engines.contains("msgf"))
//      {
//         if (enzyme == 'Trypsin') enzyme = 'Trypsin/P'
//         else if (enzyme == 'Arg-C') enzyme = 'Arg-C/P'
//         else if (enzyme == 'Asp-N') enzyme = 'Asp-N/B'
//         else if (enzyme == 'Chymotrypsin') enzyme = 'Chymotrypsin/P'
//         else if (enzyme == 'Lys-C') enzyme = 'Lys-C/P'
//      }
//      """
//      PeptideIndexer -in ${id_file} \\
//                     -out ${id_file.baseName}_idx.idXML \\
//                     -threads ${task.cpus} \\
//                     -fasta ${database} \\
//                     -enzyme:name "${enzyme}" \\
//                     -enzyme:specificity ${pepidx_num_enzyme_termini} \\
//                     ${il} \\
//                     ${allow_um} \\
//                     > ${id_file.baseName}_index_peptides.log
//      """
// }
//
//
// // ---------------------------------------------------------------------
// // Branch a) Q-values and PEP from Percolator
//
// process extract_percolator_features {
//
//     label 'process_very_low'
//     label 'process_single_thread'
//
//     publishDir "${params.outdir}/logs", mode: 'copy', pattern: '*.log'
//
//     input:
//      tuple mzml_id, file(id_file) from id_files_idx_ForPerc
//
//     output:
//      tuple mzml_id, file("${id_file.baseName}_feat.idXML") into id_files_idx_feat
//      file "*.log"
//
//     when:
//      params.posterior_probabilities == "percolator"
//
//     script:
//      """
//      PSMFeatureExtractor -in ${id_file} \\
//                          -out ${id_file.baseName}_feat.idXML \\
//                          -threads ${task.cpus} \\
//                          > ${id_file.baseName}_extract_percolator_features.log
//      """
// }
//
//
// //Note: from here, we do not need any settings anymore. so we can skip adding the mzml_id to the channels
// //TODO find a way to run across all runs merged
// process percolator {
//
//     //TODO Actually it heavily depends on the subset_max_train option and the number of IDs
//     // would be cool to get an estimate by parsing the number of IDs from previous tools.
//     label 'process_medium'
//     //Since percolator 3.5 it allows for 27 parallel tasks
//     cpus { check_max( 27, 'cpus' ) }
//
//     publishDir "${params.outdir}/logs", mode: 'copy', pattern: '*.log'
//     publishDir "${params.outdir}/raw_ids", mode: 'copy', pattern: '*.idXML'
//
//     input:
//      tuple mzml_id, file(id_file) from id_files_idx_feat
//
//     output:
//      tuple mzml_id, file("${id_file.baseName}_perc.idXML"), val("MS:1001491") into id_files_perc, id_files_perc_consID
//      file "*.log"
//
//     when:
//      params.posterior_probabilities == "percolator"
//
//     // NICE-TO-HAVE: the decoy-pattern is automatically detected from PeptideIndexer.
//     // Parse its output and put the correct one here.
//     script:
//       if (params.klammer && params.description_correct_features == 0) {
//           log.warn('Klammer was specified, but description of correct features was still 0. Please provide a description of correct features greater than 0.')
//           log.warn('Klammer will be implicitly off!')
//       }
//
//       // currently post-processing-tdc is always set since we do not support separate TD databases
//       """
//       ## Percolator does not have a threads parameter. Set it via OpenMP env variable,
//       ## to honor threads on clusters
//       OMP_NUM_THREADS=${task.cpus} PercolatorAdapter \\
//                           -in ${id_file} \\
//                           -out ${id_file.baseName}_perc.idXML \\
//                           -threads ${task.cpus} \\
//                           -subset_max_train ${params.subset_max_train} \\
//                           -decoy_pattern ${params.decoy_affix} \\
//                           -post_processing_tdc \\
//                           -score_type pep \\
//                           > ${id_file.baseName}_percolator.log
//       """
// }
//
// // ---------------------------------------------------------------------
// // Branch b) Q-values and PEP from OpenMS
//
// if(params.posterior_probabilities != "percolator" && params.search_engines.split(",").size() == 1)
// {
//   id_files_idx_ForIDPEP_noFDR = Channel.empty()
// }
// process fdr_idpep {
//
//     label 'process_very_low'
//     label 'process_single_thread'
//
//     publishDir "${params.outdir}/logs", mode: 'copy', pattern: '*.log'
//
//     input:
//      tuple mzml_id, file(id_file) from id_files_idx_ForIDPEP
//
//     output:
//      tuple mzml_id, file("${id_file.baseName}_fdr.idXML") into id_files_idx_ForIDPEP_FDR
//      file "*.log"
//
//     when:
//      params.posterior_probabilities != "percolator" && params.search_engines.split(",").size() == 1
//
//     script:
//      """
//      FalseDiscoveryRate -in ${id_file} \\
//                         -out ${id_file.baseName}_fdr.idXML \\
//                         -threads ${task.cpus} \\
//                         -protein false \\
//                         -algorithm:add_decoy_peptides \\
//                         -algorithm:add_decoy_proteins \\
//                         > ${id_file.baseName}_fdr.log
//      """
// }
//
// //idpep picks the best scores for each search engine automatically. No switching needed after FDR.
// process idpep {
//
//     label 'process_low'
//     // I think Eigen optimization is multi-threaded, so leave threads open
//
//     publishDir "${params.outdir}/logs", mode: 'copy', pattern: '*.log'
//     publishDir "${params.outdir}/raw_ids", mode: 'copy', pattern: '*.idXML'
//
//     input:
//      tuple mzml_id, file(id_file) from id_files_idx_ForIDPEP_FDR.mix(id_files_idx_ForIDPEP_noFDR)
//
//     output:
//      tuple mzml_id, file("${id_file.baseName}_idpep.idXML"), val("q-value_score") into id_files_idpep, id_files_idpep_consID
//      file "*.log"
//
//     when:
//      params.posterior_probabilities != "percolator"
//
//     script:
//      """
//      IDPosteriorErrorProbability    -in ${id_file} \\
//                                     -out ${id_file.baseName}_idpep.idXML \\
//                                     -fit_algorithm:outlier_handling ${params.outlier_handling} \\
//                                     -threads ${task.cpus} \\
//                                     > ${id_file.baseName}_idpep.log
//      """
// }
//
// // ---------------------------------------------------------------------
// // Main Branch
//
// //TODO this can be removed if we would add a "score_type" option to IDFilter that looks and filters for that score
// process idscoreswitcher_to_qval {
//
//     label 'process_very_low'
//     label 'process_single_thread'
//
//     publishDir "${params.outdir}/logs", mode: 'copy', pattern: '*.log'
//
//     input:
//      tuple mzml_id, file(id_file), val(qval_score) from id_files_idpep.mix(id_files_perc)
//
//     output:
//      tuple mzml_id, file("${id_file.baseName}_switched.idXML") into id_files_noConsID_qval
//      file "*.log"
//
//     when:
//      params.search_engines.split(",").size() == 1
//
//     script:
//      """
//      IDScoreSwitcher    -in ${id_file} \\
//                         -out ${id_file.baseName}_switched.idXML \\
//                         -threads ${task.cpus} \\
//                         -old_score "Posterior Error Probability" \\
//                         -new_score ${qval_score} \\
//                         -new_score_type q-value \\
//                         -new_score_orientation lower_better \\
//                         > ${id_file.baseName}_scoreswitcher_qval.log
//      """
// }
//
// process consensusid {
//
//     label 'process_medium'
//     //TODO could be easily parallelized
//     label 'process_single_thread'
//
//     publishDir "${params.outdir}/logs", mode: 'copy', pattern: '*.log'
//     publishDir "${params.outdir}/consensus_ids", mode: 'copy', pattern: '*.idXML'
//
//     // we can drop qval_score in this branch since we have to recalculate FDR anyway
//     input:
//      tuple mzml_id, file(id_files_from_ses), val(qval_score) from id_files_idpep_consID.mix(id_files_perc_consID).groupTuple(size: params.search_engines.split(",").size())
//
//     output:
//      tuple mzml_id, file("${mzml_id}_consensus.idXML") into consensusids
//      file "*.log"
//
//     when:
//      params.search_engines.split(",").size() > 1
//
//     script:
//      """
//      ConsensusID -in ${id_files_from_ses} \\
//                         -out ${mzml_id}_consensus.idXML \\
//                         -per_spectrum \\
//                         -threads ${task.cpus} \\
//                         -algorithm ${params.consensusid_algorithm} \\
//                         -filter:min_support ${params.min_consensus_support} \\
//                         -filter:considered_hits ${params.consensusid_considered_top_hits} \\
//                         > ${mzml_id}_consensusID.log
//      """
//
// }
//
// process fdr_consensusid {
//
//     label 'process_medium'
//     label 'process_single_thread'
//
//     publishDir "${params.outdir}/logs", mode: 'copy', pattern: '*.log'
//     publishDir "${params.outdir}/ids", mode: 'copy', pattern: '*.idXML'
//
//     input:
//      tuple mzml_id, file(id_file) from consensusids
//
//     output:
//      tuple mzml_id, file("${id_file.baseName}_fdr.idXML") into consensusids_fdr
//      file "*.log"
//
//     when:
//      params.search_engines.split(",").size() > 1
//
//     script:
//      """
//      FalseDiscoveryRate -in ${id_file} \\
//                         -out ${id_file.baseName}_fdr.idXML \\
//                         -threads ${task.cpus} \\
//                         -protein false \\
//                         -algorithm:add_decoy_peptides \\
//                         -algorithm:add_decoy_proteins \\
//                         > ${id_file.baseName}_fdr.log
//      """
//
// }
//
// process idfilter {
//
//     label 'process_very_low'
//     label 'process_single_thread'
//
//     publishDir "${params.outdir}/logs", mode: 'copy', pattern: '*.log'
//     publishDir "${params.outdir}/ids", mode: 'copy', pattern: '*.idXML'
//
//     input:
//      tuple mzml_id, file(id_file) from id_files_noConsID_qval.mix(consensusids_fdr)
//
//     output:
//      tuple mzml_id, file("${id_file.baseName}_filter.idXML") into id_filtered, id_filtered_luciphor
//      file "*.log"
//
//     script:
//      """
//      IDFilter -in ${id_file} \\
//                         -out ${id_file.baseName}_filter.idXML \\
//                         -threads ${task.cpus} \\
//                         -score:pep ${params.psm_pep_fdr_cutoff} \\
//                         > ${id_file.baseName}_idfilter.log
//      """
// }
//
// plfq_in_id = params.enable_mod_localization
//                     ? Channel.empty()
//                     : id_filtered
//
// // TODO make luciphor pick its own score so we can skip this step
// process idscoreswitcher_for_luciphor {
//
//     label 'process_very_low'
//     label 'process_single_thread'
//
//     publishDir "${params.outdir}/logs", mode: 'copy', pattern: '*.log'
//
//     input:
//      tuple mzml_id, file(id_file) from id_filtered_luciphor
//
//     output:
//      tuple mzml_id, file("${id_file.baseName}_pep.idXML") into id_filtered_luciphor_pep
//      file "*.log"
//
//     when:
//      params.enable_mod_localization
//
//     script:
//      """
//      IDScoreSwitcher    -in ${id_file} \\
//                         -out ${id_file.baseName}_pep.idXML \\
//                         -threads ${task.cpus} \\
//                         -old_score "q-value" \\
//                         -new_score "Posterior Error Probability_score" \\
//                         -new_score_type "Posterior Error Probability" \\
//                         -new_score_orientation lower_better \\
//                         > ${id_file.baseName}_switch_pep_for_luciphor.log
//
//      """
// }
//
// process luciphor {
//
//     label 'process_medium'
//
//     publishDir "${params.outdir}/logs", mode: 'copy', pattern: '*.log'
//
//     input:
//      tuple mzml_id, file(mzml_file), file(id_file), frag_method from mzmls_luciphor.join(id_filtered_luciphor_pep).join(ch_sdrf_config.luciphor_settings)
//
//     output:
//      set mzml_id, file("${id_file.baseName}_luciphor.idXML") into plfq_in_id_luciphor
//      file "*.log"
//
//     when:
//      params.enable_mod_localization
//
//     script:
//      def losses = params.luciphor_neutral_losses ? '-neutral_losses "${params.luciphor_neutral_losses}"' : ''
//      def dec_mass = params.luciphor_decoy_mass ? '-decoy_mass "${params.luciphor_decoy_mass}"' : ''
//      def dec_losses = params.luciphor_decoy_neutral_losses ? '-decoy_neutral_losses "${params.luciphor_decoy_neutral_losses}' : ''
//      """
//      LuciphorAdapter    -id ${id_file} \\
//                         -in ${mzml_file} \\
//                         -out ${id_file.baseName}_luciphor.idXML \\
//                         -threads ${task.cpus} \\
//                         -num_threads ${task.cpus} \\
//                         -target_modifications ${params.mod_localization.tokenize(',').collect { "'${it}'" }.join(" ") } \\
//                         -fragment_method ${frag_method} \\
//                         ${losses} \\
//                         ${dec_mass} \\
//                         ${dec_losses} \\
//                         -max_charge_state ${params.max_precursor_charge} \\
//                         -max_peptide_length ${params.max_peptide_length} \\
//                         -debug ${params.luciphor_debug} \\
//                         > ${id_file.baseName}_luciphor.log
//      """
//                      //        -fragment_mass_tolerance ${} \\
//                      //   -fragment_error_units ${} \\
// }
//
// // Join mzmls and ids by UID specified per mzml file in the beginning.
// // ID files can come directly from the Percolator branch, IDPEP branch or
// // after optional processing with Luciphor
// mzmls_plfq.mix(mzmls_plfq_picked)
//   .join(plfq_in_id.mix(plfq_in_id_luciphor))
//   .multiMap{ it ->
//       mzmls: it[1]
//       ids: it[2]
//   }
//   .set{ch_plfq}
//
// process proteomicslfq {
//
//     label 'process_high'
//
//     publishDir "${params.outdir}/logs", mode: 'copy', pattern: '*.log'
//     publishDir "${params.outdir}/proteomics_lfq", mode: 'copy'
//
//     ///.toSortedList({ a, b -> b.baseName <=> a.baseName })
//     input:
//      file(mzmls) from ch_plfq.mzmls.collect()
//      file(id_files) from ch_plfq.ids.collect()
//      file expdes from ch_expdesign
//      file fasta from plfq_in_db.mix(plfq_in_db_decoy)
//
//     output:
//      file "out.mzTab" into out_mztab_plfq, out_mztab_msstats
//      file "out.consensusXML" into out_consensusXML
//      file "out.csv" optional true into out_msstats
//      file "debug_mergedIDs.idXML" optional true
//      file "debug_mergedIDs_inference.idXML" optional true
//      file "debug_mergedIDsGreedyResolved.idXML" optional true
//      file "debug_mergedIDsGreedyResolvedFDR.idXML" optional true
//      file "debug_mergedIDsGreedyResolvedFDRFiltered.idXML" optional true
//      file "debug_mergedIDsFDRFilteredStrictlyUniqueResolved.idXML" optional true
//      file "*.log"
//
//     script:
//      def msstats_present = params.quantification_method == "feature_intensity" ? '-out_msstats out.csv' : ''
//      """
//      ProteomicsLFQ -in ${(mzmls as List).join(' ')} \\
//                    -ids ${(id_files as List).join(' ')} \\
//                    -design ${expdes} \\
//                    -fasta ${fasta} \\
//                    -protein_inference ${params.protein_inference} \\
//                    -quantification_method ${params.quantification_method} \\
//                    -targeted_only ${params.targeted_only} \\
//                    -mass_recalibration ${params.mass_recalibration} \\
//                    -transfer_ids ${params.transfer_ids} \\
//                    -protein_quantification ${params.protein_quant} \\
//                    -out out.mzTab \\
//                    -threads ${task.cpus} \\
//                    ${msstats_present} \\
//                    -out_cxml out.consensusXML \\
//                    -proteinFDR ${params.protein_level_fdr_cutoff} \\
//                    -debug ${params.inf_quant_debug} \\
//                    > proteomicslfq.log
//          """
//
// }
//
//
// // TODO the script supports a control condition as third argument
// // TODO the second argument can be "pairwise" or TODO later a user defined contrast string
//
// process msstats {
//
//     label 'process_medium'
//
//     publishDir "${params.outdir}/logs", mode: 'copy', pattern: '*.log'
//     publishDir "${params.outdir}/msstats", mode: 'copy'
//
//     when:
//      !params.skip_post_msstats && params.quantification_method == "feature_intensity"
//
//     input:
//      file csv from out_msstats
//      file mztab from out_mztab_msstats
//
//     output:
//      // The generation of the PDFs from MSstats are very unstable, especially with auto-contrasts.
//      // And users can easily fix anything based on the csv and the included script -> make optional
//      file "*.pdf" optional true
//      file "*.mzTab" optional true
//      file "*.csv"
//      file "*.log"
//
//     script:
//      """
//      msstats_plfq.R ${csv} ${mztab} > msstats.log || echo "Optional MSstats step failed. Please check logs and re-run or do a manual statistical analysis."
//      """
// }
//
// //TODO allow user config yml (as second arg to the script
//
// process ptxqc {
//
//     label 'process_low'
//     label 'process_single_thread'
//
//     publishDir "${params.outdir}/logs", mode: 'copy', pattern: '*.log'
//     publishDir "${params.outdir}/ptxqc", mode: 'copy'
//
//     when:
//      params.enable_qc
//
//     input:
//      file mzTab from out_mztab_plfq
//
//     output:
//      file "*.html" into ch_ptxqc_report
//      file "*.yaml"
//      file "*.Rmd"
//      file "*.pdf"
//      file "*.txt"
//
//     script:
//      """
//      ptxqc.R ${mzTab} > ptxqc.log
//      """
// }
//
// if (!params.enable_qc)
// {
//   ch_ptxqc_report = Channel.empty()
// }


//--------------------------------------------------------------- //
//---------------------- Nextflow specifics --------------------- //
//--------------------------------------------------------------- //


// Header log info
log.info nfcoreHeader()
def summary = [:]
if (workflow.revision) summary['Pipeline Release'] = workflow.revision
summary['Run Name']         = custom_runName ?: workflow.runName
summary['Max Resources']    = "$params.max_memory memory, $params.max_cpus cpus, $params.max_time time per job"
if (workflow.containerEngine) summary['Container'] = "$workflow.containerEngine - $workflow.container"
summary['Output dir']       = params.outdir
summary['Launch dir']       = workflow.launchDir
summary['Working dir']      = workflow.workDir
summary['Script dir']       = workflow.projectDir
summary['User']             = workflow.userName
if (workflow.profile.contains('awsbatch')) {
    summary['AWS Region']   = params.awsregion
    summary['AWS Queue']    = params.awsqueue
    summary['AWS CLI']      = params.awscli
}
summary['Config Profile'] = workflow.profile
if (params.config_profile_description) summary['Config Profile Description'] = params.config_profile_description
if (params.config_profile_contact)     summary['Config Profile Contact']     = params.config_profile_contact
if (params.config_profile_url)         summary['Config Profile URL']         = params.config_profile_url
summary['Config Files'] = workflow.configFiles.join(', ')
if (params.email || params.email_on_fail) {
    summary['E-mail Address']    = params.email
    summary['E-mail on failure'] = params.email_on_fail
}
log.info summary.collect { k,v -> "${k.padRight(18)}: $v" }.join("\n")
log.info "-\033[2m--------------------------------------------------\033[0m-"

// Check the hostnames against configured profiles
checkHostname()

Channel.from(summary.collect{ [it.key, it.value] })
    .map { k,v -> "<dt>$k</dt><dd><samp>${v ?: '<span style=\"color:#999999;\">N/A</a>'}</samp></dd>" }
    .reduce { a, b -> return [a, b].join("\n            ") }
    .map { x -> """
    id: 'nf-core-proteomicslfq-summary'
    description: " - this information is collected when the pipeline is started."
    section_name: 'nf-core/proteomicslfq Workflow Summary'
    section_href: 'https://github.com/nf-core/proteomicslfq'
    plot_type: 'html'
    data: |
        <dl class=\"dl-horizontal\">
            $x
        </dl>
    """.stripIndent() }
    .set { ch_workflow_summary }

/*
 * Parse software version numbers
 */
process get_software_versions {
    publishDir "${params.outdir}/pipeline_info", mode: params.publish_dir_mode,
        saveAs: { filename ->
                      if (filename.indexOf(".csv") > 0) filename
                      else null
                }

    output:
    file 'software_versions_mqc.yaml' into ch_software_versions_yaml
    file "software_versions.csv"

    script:
    """
    echo $workflow.manifest.version > v_pipeline.txt
    echo $workflow.nextflow.version > v_nextflow.txt
    echo $workflow.manifest.version &> v_msstats_plfq.txt
    scrape_software_versions.py &> software_versions_mqc.yaml
    """
}

/*
 * STEP 3 - Output Description HTML
 */
process output_documentation {
    publishDir "${params.outdir}/pipeline_info", mode: params.publish_dir_mode

    input:
    file output_docs from ch_output_docs
    file images from ch_output_docs_images

    output:
    file "results_description.html"

    script:
    """
    markdown_to_html.py $output_docs -o results_description.html
    """
}

/*
 * Completion e-mail notification
 */
workflow.onComplete {

    // Set up the e-mail variables
    def subject = "[nf-core/proteomicslfq] Successful: $workflow.runName"
    if (!workflow.success) {
        subject = "[nf-core/proteomicslfq] FAILED: $workflow.runName"
    }
    def email_fields = [:]
    email_fields['version'] = workflow.manifest.version
    email_fields['runName'] = custom_runName ?: workflow.runName
    email_fields['success'] = workflow.success
    email_fields['dateComplete'] = workflow.complete
    email_fields['duration'] = workflow.duration
    email_fields['exitStatus'] = workflow.exitStatus
    email_fields['errorMessage'] = (workflow.errorMessage ?: 'None')
    email_fields['errorReport'] = (workflow.errorReport ?: 'None')
    email_fields['commandLine'] = workflow.commandLine
    email_fields['projectDir'] = workflow.projectDir
    email_fields['summary'] = summary
    email_fields['summary']['Date Started'] = workflow.start
    email_fields['summary']['Date Completed'] = workflow.complete
    email_fields['summary']['Pipeline script file path'] = workflow.scriptFile
    email_fields['summary']['Pipeline script hash ID'] = workflow.scriptId
    if (workflow.repository) email_fields['summary']['Pipeline repository Git URL'] = workflow.repository
    if (workflow.commitId) email_fields['summary']['Pipeline repository Git Commit'] = workflow.commitId
    if (workflow.revision) email_fields['summary']['Pipeline Git branch/tag'] = workflow.revision
    email_fields['summary']['Nextflow Version'] = workflow.nextflow.version
    email_fields['summary']['Nextflow Build'] = workflow.nextflow.build
    email_fields['summary']['Nextflow Compile Timestamp'] = workflow.nextflow.timestamp

    // On success try attach the multiqc report
    def mqc_report = ""
    try {
        if (workflow.success && ch_ptxqc_report.println()) {
            mqc_report = ch_ptxqc_report.getVal()
            if (mqc_report.getClass() == ArrayList) {
                log.warn "[nf-core/proteomicslfq] Found multiple reports from process 'ptxqc', will use only one"
                mqc_report = mqc_report[0]
            }
        }
        else {
          mqc_report = ""
        }
    } catch (all) {
        log.warn "[nf-core/proteomicslfq] Could not attach PTXQC report to summary email"
    }

    // Check if we are only sending emails on failure
    email_address = params.email
    if (!params.email && params.email_on_fail && !workflow.success) {
        email_address = params.email_on_fail
    }

    // Render the TXT template
    def engine = new groovy.text.GStringTemplateEngine()
    def tf = new File("$baseDir/assets/email_template.txt")
    def txt_template = engine.createTemplate(tf).make(email_fields)
    def email_txt = txt_template.toString()

    // Render the HTML template
    def hf = new File("$baseDir/assets/email_template.html")
    def html_template = engine.createTemplate(hf).make(email_fields)
    def email_html = html_template.toString()

    // Render the sendmail template
    def smail_fields = [ email: email_address, subject: subject, email_txt: email_txt, email_html: email_html, baseDir: "$baseDir", mqcFile: mqc_report, mqcMaxSize: params.max_multiqc_email_size.toBytes() ]
    def sf = new File("$baseDir/assets/sendmail_template.txt")
    def sendmail_template = engine.createTemplate(sf).make(smail_fields)
    def sendmail_html = sendmail_template.toString()

    // Send the HTML e-mail
    if (email_address) {
        try {
            if (params.plaintext_email) { throw GroovyException('Send plaintext e-mail, not HTML') }
            // Try to send HTML e-mail using sendmail
            [ 'sendmail', '-t' ].execute() << sendmail_html
            log.info "[nf-core/proteomicslfq] Sent summary e-mail to $email_address (sendmail)"
        } catch (all) {
            // Catch failures and try with plaintext
            def mail_cmd = [ 'mail', '-s', subject, '--content-type=text/html', email_address ]
            if ( mqc != "" && mqc_report.size() <= params.max_multiqc_email_size.toBytes() ) {
              mail_cmd += [ '-A', mqc_report ]
            }
            mail_cmd.execute() << email_html
            log.info "[nf-core/proteomicslfq] Sent summary e-mail to $email_address (mail)"
        }
    }

    // Write summary e-mail HTML to a file
    def output_d = new File("${params.outdir}/pipeline_info/")
    if (!output_d.exists()) {
        output_d.mkdirs()
    }
    def output_hf = new File(output_d, "pipeline_report.html")
    output_hf.withWriter { w -> w << email_html }
    def output_tf = new File(output_d, "pipeline_report.txt")
    output_tf.withWriter { w -> w << email_txt }

    c_green = params.monochrome_logs ? '' : "\033[0;32m";
    c_purple = params.monochrome_logs ? '' : "\033[0;35m";
    c_red = params.monochrome_logs ? '' : "\033[0;31m";
    c_reset = params.monochrome_logs ? '' : "\033[0m";

    if (workflow.stats.ignoredCount > 0 && workflow.success) {
        log.info "-${c_purple}Warning, pipeline completed, but with errored process(es) ${c_reset}-"
        log.info "-${c_red}Number of ignored errored process(es) : ${workflow.stats.ignoredCount} ${c_reset}-"
        log.info "-${c_green}Number of successfully ran process(es) : ${workflow.stats.succeedCount} ${c_reset}-"
    }

    if (workflow.success) {
        log.info "-${c_purple}[nf-core/proteomicslfq]${c_green} Pipeline completed successfully${c_reset}-"
    } else {
        checkHostname()
        log.info "-${c_purple}[nf-core/proteomicslfq]${c_red} Pipeline completed with errors${c_reset}-"
    }

}


def nfcoreHeader() {
    // Log colors ANSI codes
    c_black = params.monochrome_logs ? '' : "\033[0;30m";
    c_blue = params.monochrome_logs ? '' : "\033[0;34m";
    c_cyan = params.monochrome_logs ? '' : "\033[0;36m";
    c_dim = params.monochrome_logs ? '' : "\033[2m";
    c_green = params.monochrome_logs ? '' : "\033[0;32m";
    c_purple = params.monochrome_logs ? '' : "\033[0;35m";
    c_reset = params.monochrome_logs ? '' : "\033[0m";
    c_white = params.monochrome_logs ? '' : "\033[0;37m";
    c_yellow = params.monochrome_logs ? '' : "\033[0;33m";

    return """    -${c_dim}--------------------------------------------------${c_reset}-
                                            ${c_green},--.${c_black}/${c_green},-.${c_reset}
    ${c_blue}        ___     __   __   __   ___     ${c_green}/,-._.--~\'${c_reset}
    ${c_blue}  |\\ | |__  __ /  ` /  \\ |__) |__         ${c_yellow}}  {${c_reset}
    ${c_blue}  | \\| |       \\__, \\__/ |  \\ |___     ${c_green}\\`-._,-`-,${c_reset}
                                            ${c_green}`._,._,\'${c_reset}
    ${c_purple}  nf-core/proteomicslfq v${workflow.manifest.version}${c_reset}
    -${c_dim}--------------------------------------------------${c_reset}-
    """.stripIndent()
}

def checkHostname() {
    def c_reset = params.monochrome_logs ? '' : "\033[0m"
    def c_white = params.monochrome_logs ? '' : "\033[0;37m"
    def c_red = params.monochrome_logs ? '' : "\033[1;91m"
    def c_yellow_bold = params.monochrome_logs ? '' : "\033[1;93m"
    if (params.hostnames) {
        def hostname = "hostname".execute().text.trim()
        params.hostnames.each { prof, hnames ->
            hnames.each { hname ->
                if (hostname.contains(hname) && !workflow.profile.contains(prof)) {
                    log.error "====================================================\n" +
                            "  ${c_red}WARNING!${c_reset} You are running with `-profile $workflow.profile`\n" +
                            "  but your machine hostname is ${c_white}'$hostname'${c_reset}\n" +
                            "  ${c_yellow_bold}It's highly recommended that you use `-profile $prof${c_reset}`\n" +
                            "============================================================"
                }
            }
        }
    }
}


//--------------------------------------------------------------- //
//---------------------- Utility functions  --------------------- //
//--------------------------------------------------------------- //

// Check file extension
def hasExtension(it, extension) {
    it.toString().toLowerCase().endsWith(extension.toLowerCase())
}

// Check class of an Object for "List" type
boolean isCollectionOrArray(object) {
    [Collection, Object[]].any { it.isAssignableFrom(object.getClass()) }
}