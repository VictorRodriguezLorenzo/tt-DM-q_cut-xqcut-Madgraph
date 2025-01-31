#!/bin/sh

# Controllers for the whole code
GENERATE_MASS_POINTS=false
GENERATE_GRIDPACKS=false
PERFORM_HADRONIZATION=true
FIND_BEST_CONFIGURATION=false
GENERATE_PLOTS=false

# Define directories for the scripts and logs
SCRIPT_DIR="/afs/cern.ch/user/v/victorr/private/tt_DM/full_workflow"
GRIDPACK_SCRIPT="${SCRIPT_DIR}/generate_gridpacks.sh"
MASS_POINTS_DIR="$SCRIPT_DIR/mass_points"


# Check if the generate_gridpacks script exists
if [[ ! -f "$GRIDPACK_SCRIPT" ]]; then
    echo "Error: generate_gridpacks.sh not found!"
    exit 1
fi

if [[ "${GENERATE_MASS_POINTS}" = true ]]; then
    # Step 1: Generate cards for different mass points
    echo "Step 1: Generating cards for different mass points..."
    cd "$SCRIPT_DIR"
    ./writeallcards_ttbarDM_dilepton_pseudoscalar.sh

    if [[ $? -eq 0 ]]; then
        echo "Cards for different mass points generated successfully!"
    else
        echo "Error: Failed to generate cards!"
        exit 1
    fi
fi

if [[ "$GENERATE_GRIDPACKS" = true ]]; then
    # Step 2: Iterate over all mass points to generate gridpacks with different values of xqcut
    echo "Step 2: Generating gridpacks for different xqcut values..."

    # Assuming mass points directories are in the format ttbarDM_<mass_point_name>
    for mass_point in "$SCRIPT_DIR/mass_points/"*/; do  # Assuming the mass points are directories
        if [[ -d "$mass_point" ]]; then  # Make sure it's a directory
            # Extract mass point name from the directory name
            if [[ "$mass_point" =~ ttbarDM__([^/]+) ]]; then  # Match your directory naming convention
                mass_point_name=${BASH_REMATCH[1]}  # Capture the mass point name

                echo "Processing mass point: $mass_point_name"

                # Iterate over different xqcut values (for example, from 10 to 50 with step 10)
                for xqcut_val in $(seq 10 10 50); do
                    echo "Generating gridpack for xqcut=$xqcut_val and mass_point_name=$mass_point_name"

                    # Generate gridpack with the appropriate xqcut and mass_point_name values
                    cd "$SCRIPT_DIR"  # Ensure we are in the script directory for running the gridpack generation
                    bash "$GRIDPACK_SCRIPT" "$xqcut_val" "$mass_point_name"

                    if [[ $? -eq 0 ]]; then
                        echo -e "Gridpack generated for xqcut=$xqcut_val and mass_point_name=$mass_point_name \n\n"
                    else
                        echo "Error: Failed to generate gridpack for xqcut=$xqcut_val and mass_point_name=$mass_point_name"
                        exit 1
                    fi
                done
            else
                echo "Skipping invalid directory: $mass_point"
            fi
        fi
    done
fi


CMSSW_EOS_DIR="/eos/user/v/victorr/CMSSW_13_2_9/src"
CMSSW_DIR="$SCRIPT_DIR/CMSSW_13_2_9/src"
CONDOR_SCRIPT="$CMSSW_DIR/runEventGeneration_tmp_to_eos.py"
RESUBMIT_SCRIPT="${CMSSW_DIR}/resubmit_failed_jobs.sh"
FRAGMENT_FILE="/eos/user/v/victorr/CMSSW_13_2_9/src/Configuration/GenProduction/python/EXO-RunIIFall18GS-test.py"
ROOT_FILES_DIR="$CMSSW_EOS_DIR/Event_generation"
HISTOGRAMS_FILES_DIR="$CMSSW_EOS_DIR/Histograms"
PLOTDJR_SCRIPT="$SCRIPT_DIR/plotdjr.C"
DISCONTINUITY_SCRIPT="$SCRIPT_DIR/get_discontinuity.py"
METRICS_DIR="$CMSSW_EOS_DIR/Metrics"

if [[ "$PERFORM_HADRONIZATION" = true ]]; then
    echo "Step 3 and 4: Hadronization, job submission, histograms, and metrics generation..."

    cd "$CMSSW_DIR"

    process_qcut() {
        local gridpack=$1
        local base_name=$(basename "$gridpack" .tar.xz)
        local xqcut=$(echo "$base_name" | grep -oP "xqcut_\d+" | grep -oP "\d+")
        local qcut=$2

        echo "Processing gridpack: $gridpack (xqcut=$xqcut, qcut=$qcut)"

        mkdir -p "$CMSSW_EOS_DIR/Event_generation/$base_name/qcut_${qcut}"

        # Submit jobs to HTCondor
        echo "Submitting jobs to HTCondor..."
        python3 "$CONDOR_SCRIPT" -g "$gridpack" -c "$qcut" -r "${base_name}_qcut_${qcut}" \
            -o "$CMSSW_EOS_DIR/Event_generation/${base_name}/qcut_${qcut}" \
            -a "$CMSSW_DIR/logs/${base_name}/qcut_${qcut}" -n 2500 -e 50

        # Monitor job progress
        completed=false

        while [[ $completed == false ]]; do
            sleep 60
            bash "$RESUBMIT_SCRIPT" "$CMSSW_DIR/logs/${base_name}/qcut_${qcut}"

            job_summary=$(condor_q | grep "Total for $USER:")

            if [[ -n "$job_summary" ]]; then
                total_jobs=$(echo "$job_summary" | awk -F ';' '{print $1}' | awk '{print $4}')
                completed_jobs=$(echo "$job_summary" | awk -F ';' '{print $2}' | awk '{print $1}')
                idle_jobs=$(echo "$job_summary" | awk -F ',' '{print $3}' | awk '{print $1}')
                running_jobs=$(echo "$job_summary" | awk -F ',' '{print $4}' | awk '{print $1}')
                held_jobs=$(echo "$job_summary" | awk -F ',' '{print $5}' | awk '{print $1}')

                echo "Total: $total_jobs, Idle: $idle_jobs, Running: $running_jobs, Held: $held_jobs"

                if [[ "$completed_jobs" -eq "$total_jobs" && "$idle_jobs" -eq 0 && "$running_jobs" -eq 0 && "$held_jobs" -eq 0 ]]; then
                    echo "All jobs for $base_name with qcut=$qcut are complete!"
                    completed=true
                else
                    echo "Jobs still in progress. Retrying in 1 minute..."
                fi
            else
                echo "Unable to retrieve job status. Retrying in 1 minute..."
            fi
        done

        # Combine ROOT files
        cd $CMSSW_EOS_DIR/Event_generation/${base_name}/qcut_${qcut}
        cmsenv
        hadd -f -k "$CMSSW_EOS_DIR/Event_generation/${base_name}/qcut_${qcut}/${base_name}_qcut_${qcut}_combined.root" \
            "$CMSSW_EOS_DIR/Event_generation/${base_name}/qcut_${qcut}"/*/*.root
        rm -r $CMSSW_EOS_DIR/Event_generation/${base_name}/qcut_${qcut}/run_*

        # Generate histograms
        root_file="$CMSSW_EOS_DIR/Event_generation/${base_name}/qcut_${qcut}/${base_name}_qcut_${qcut}_combined.root"
        outfile="$HISTOGRAMS_FILES_DIR/${base_name}_qcut_${qcut}_plots.pdf"
        outroot="$HISTOGRAMS_FILES_DIR/${base_name}_qcut_${qcut}.root"

	mkdir -p "$CMSSW_EOS_DIR/Histograms"
        echo "Generating histograms for xqcut=$xqcut, qcut=$qcut..."
        root -l -b -q "${PLOTDJR_SCRIPT}(\"$root_file\", \"$outfile\", \"$outroot\")"
	rm $CMSSW_EOS_DIR/Event_generation/${base_name}/qcut_${qcut}/${base_name}_qcut_${qcut}_combined.root
    }

    export -f process_qcut
    export CMSSW_DIR CMSSW_EOS_DIR CONDOR_SCRIPT RESUBMIT_SCRIPT FRAGMENT_FILE ROOT_FILES_DIR HISTOGRAMS_FILES_DIR PLOTDJR_SCRIPT DISCONTINUITY_SCRIPT METRICS_DIR

    for gridpack in "$SCRIPT_DIR/gridpacks/"*/*.tar.xz; do
        if [[ -f "$gridpack" ]]; then
            base_name=$(basename "$gridpack" .tar.xz)
            xqcut=$(echo "$base_name" | grep -oP "xqcut_\d+" | grep -oP "\d+")

            seq "$xqcut" 10 100 | parallel process_qcut "$gridpack"
        else
            echo "Skipping invalid gridpack: $gridpack"
        fi
    done

    echo "Hadronization, histograms, and metrics generation (steps 3 and 4) complete!"
fi


METRIC_BEST_RESUTS_FILE="$SCRIPT_DIR/results_metric.txt"

if [[ "$FIND_BEST_CONFIGURATION" = true ]]; then
# Step 5: Find best configuration and optionally remove others

# After the processing loop that generates the metric.txt files

# Create or clear the best_configuration.txt file
best_config_file="$SCRIPT_DIR/best_configuration.txt"
echo "mass_point, xqcut, qcut, discontinuity" > "$best_config_file"

# Iterate over all mass point directories inside METRICS_DIR
for mass_point_dir in "$METRICS_DIR"/*; do
    if [[ ! -d "$mass_point_dir" ]]; then
        continue  # Skip if it's not a directory
    fi

    mass_point=$(basename "$mass_point_dir")
    metric_file="$mass_point_dir/metric.txt"

    if [[ ! -f "$metric_file" ]]; then
        echo "No metric.txt found for mass point: $mass_point"
        continue  # Skip if no metric.txt file is found
    fi

    # Find the best configuration by sorting metric.txt based on discontinuity value
    # (Assuming that the discontinuity value is the last column in the metric.txt file)
    best_config=$(sort -t, -k4 -n "$metric_file" | head -n 1)

    # Extract mass_point, xqcut, qcut, discontinuity from the best configuration line
    xqcut_best=$(echo "$best_config" | cut -d, -f2)
    qcut_best=$(echo "$best_config" | cut -d, -f3)
    discontinuity_best=$(echo "$best_config" | cut -d, -f4)

    # Append the best configuration to the best_configuration.txt file
    echo "$mass_point, $xqcut_best, $qcut_best, $discontinuity_best" >> "$best_config_file"

done

echo "Best configurations have been saved to $best_config_file."
    echo "Step 5 complete!"
fi

if [[ "$GENERATE_PLOTS" = true ]]; then
    echo "Step X: Generating plots for DJR continuity metrics..."

    # Base directory containing metrics
    METRICS_DIR="$CMSSW_EOS_DIR/Metrics"  # Replace with the actual directory path
    PLOTS_OUTPUT_BASE_DIR="$CMSSW_EOS_DIR/Contuour_plots"  # Base directory for saving plots

    mkdir -p $PLOTS_OUTPUT_BASE_DIR

    # Iterate over all metric.txt files in the METRICS_DIR
    find "$METRICS_DIR" -name "metric.txt" | while read -r METRICS_FILE; do
        # Extract the mass point (parent directory name)
        MASS_POINT=$(basename "$(dirname "$METRICS_FILE")")

        # Define the output directory for plots for this mass point
        PLOTS_OUTPUT_DIR="${PLOTS_OUTPUT_BASE_DIR}/${MASS_POINT}"

        echo "Processing metrics for mass point: $MASS_POINT"

        # Run the Python script
        python3 plot_metrics.py --input "$METRICS_FILE" --output_dir "$PLOTS_OUTPUT_DIR" --enable_plots

        if [[ $? -eq 0 ]]; then
            echo "Plots for $MASS_POINT generated successfully!"
        else
            echo "Error: Failed to generate plots for $MASS_POINT!"
            exit 1
        fi
    done
else
    echo "Plot generation is disabled."
fi


echo "Process completed."

