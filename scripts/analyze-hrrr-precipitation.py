#!/usr/bin/env python3
"""
HRRR Precipitation Analysis for Oso Creek / Corpus Christi Basin

This script processes the extracted HRRR precipitation rate data to compute:
- Basin-wide averages
- Percentiles (5th, 25th, 50th, 75th, 95th)
- Time series statistics
- Spatial aggregation

Input: CSV files from aws-process-hrrr-oso-creek.sh
Output: Aggregated statistics and analysis results
"""

import pandas as pd
import numpy as np
import glob
import os
import argparse
import zipfile
import tempfile
from pathlib import Path
from datetime import datetime, timedelta
import logging

# Set up logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

class HRRRPrecipitationAnalyzer:
    def __init__(self, data_dir, output_dir):
        """
        Initialize the analyzer
        
        Args:
            data_dir (str): Directory containing the extracted HRRR CSV files (zip format)
            output_dir (str): Directory to save analysis results
        """
        self.data_dir = Path(data_dir)
        self.output_dir = Path(output_dir)
        self.output_dir.mkdir(parents=True, exist_ok=True)
        
        # Basin characteristics
        self.basin_name = "Oso Creek / Corpus Christi"
        self.lat_min = 27.588733
        self.lat_max = 27.837343
        self.lon_min = -97.729247
        self.lon_max = -97.251896
        
        logger.info(f"Initialized analyzer for {self.basin_name}")
        logger.info(f"Basin bounds: Lat({self.lat_min}, {self.lat_max}), Lon({self.lon_min}, {self.lon_max})")
    
    def extract_zip_files(self):
        """Extract all zip files in the data directory"""
        zip_files = list(self.data_dir.glob("*.zip"))
        logger.info(f"Found {len(zip_files)} zip files to process")
        
        extracted_files = []
        temp_dir = tempfile.mkdtemp()
        
        for zip_file in zip_files:
            try:
                with zipfile.ZipFile(zip_file, 'r') as zf:
                    zf.extractall(temp_dir)
                    for extracted in zf.namelist():
                        extracted_files.append(os.path.join(temp_dir, extracted))
            except Exception as e:
                logger.error(f"Error extracting {zip_file}: {e}")
        
        return extracted_files, temp_dir
    
    def load_data(self):
        """Load all CSV data files"""
        logger.info("Loading precipitation data...")
        
        # Extract zip files first
        csv_files, temp_dir = self.extract_zip_files()
        
        # Filter for CSV files
        csv_files = [f for f in csv_files if f.endswith('.csv')]
        logger.info(f"Found {len(csv_files)} CSV files")
        
        if not csv_files:
            raise ValueError("No CSV files found in the data directory")
        
        all_data = []
        
        for csv_file in csv_files:
            try:
                df = pd.read_csv(csv_file)
                if len(df) > 0:
                    all_data.append(df)
                logger.debug(f"Loaded {len(df)} records from {os.path.basename(csv_file)}")
            except Exception as e:
                logger.error(f"Error loading {csv_file}: {e}")
        
        if not all_data:
            raise ValueError("No valid data found in CSV files")
        
        # Combine all data
        combined_df = pd.concat(all_data, ignore_index=True)
        logger.info(f"Total records loaded: {len(combined_df)}")
        
        # Clean up temporary directory
        import shutil
        shutil.rmtree(temp_dir)
        
        return combined_df
    
    def preprocess_data(self, df):
        """Preprocess the data for analysis"""
        logger.info("Preprocessing data...")
        
        # Convert datetime column to datetime type
        df['datetime'] = pd.to_datetime(df['datetime'])
        
        # Convert forecast_lead to integer
        df['forecast_lead'] = df['forecast_lead'].astype(int)
        
        # Create additional time columns
        df['date'] = df['datetime'].dt.date
        df['hour'] = df['datetime'].dt.hour
        df['month'] = df['datetime'].dt.month
        df['year'] = df['datetime'].dt.year
        df['season'] = df['month'].map({12: 'Winter', 1: 'Winter', 2: 'Winter',
                                       3: 'Spring', 4: 'Spring', 5: 'Spring',
                                       6: 'Summer', 7: 'Summer', 8: 'Summer',
                                       9: 'Fall', 10: 'Fall', 11: 'Fall'})
        
        # Calculate valid time (forecast time)
        df['valid_time'] = df['datetime'] + pd.to_timedelta(df['forecast_lead'], unit='h')
        
        # Filter out any potential invalid data
        df = df[df['prate_mm_hr'] >= 0]  # Precipitation should be non-negative
        
        logger.info(f"Preprocessed data shape: {df.shape}")
        logger.info(f"Date range: {df['datetime'].min()} to {df['datetime'].max()}")
        logger.info(f"Forecast leads: {df['forecast_lead'].min()} to {df['forecast_lead'].max()}")
        
        return df
    
    def compute_basin_statistics(self, df):
        """Compute basin-wide statistics for each forecast time"""
        logger.info("Computing basin-wide statistics...")
        
        # Group by datetime, forecast_lead, and valid_time to compute spatial statistics
        spatial_stats = df.groupby(['datetime', 'forecast_lead', 'valid_time']).agg({
            'prate_mm_hr': ['count', 'mean', 'std', 'min', 'max', 
                           lambda x: np.percentile(x, 5),
                           lambda x: np.percentile(x, 25),
                           lambda x: np.percentile(x, 50),
                           lambda x: np.percentile(x, 75),
                           lambda x: np.percentile(x, 95)]
        }).round(6)
        
        # Flatten column names
        spatial_stats.columns = ['grid_count', 'basin_mean', 'basin_std', 'basin_min', 'basin_max',
                                'basin_p05', 'basin_p25', 'basin_p50', 'basin_p75', 'basin_p95']
        
        spatial_stats = spatial_stats.reset_index()
        
        logger.info(f"Computed statistics for {len(spatial_stats)} forecast times")
        
        return spatial_stats
    
    def compute_temporal_statistics(self, basin_stats):
        """Compute temporal statistics"""
        logger.info("Computing temporal statistics...")
        
        # Overall statistics
        overall_stats = {
            'total_forecasts': len(basin_stats),
            'date_range_start': basin_stats['datetime'].min(),
            'date_range_end': basin_stats['datetime'].max(),
            'mean_precipitation': basin_stats['basin_mean'].mean(),
            'std_precipitation': basin_stats['basin_mean'].std(),
            'max_precipitation': basin_stats['basin_max'].max(),
            'percentiles': {
                'p05': np.percentile(basin_stats['basin_mean'], 5),
                'p25': np.percentile(basin_stats['basin_mean'], 25),
                'p50': np.percentile(basin_stats['basin_mean'], 50),
                'p75': np.percentile(basin_stats['basin_mean'], 75),
                'p95': np.percentile(basin_stats['basin_mean'], 95)
            }
        }
        
        # Add temporal grouping columns
        basin_stats['date'] = basin_stats['datetime'].dt.date
        basin_stats['hour'] = basin_stats['datetime'].dt.hour
        basin_stats['month'] = basin_stats['datetime'].dt.month
        basin_stats['year'] = basin_stats['datetime'].dt.year
        
        # Monthly statistics
        monthly_stats = basin_stats.groupby('month')['basin_mean'].agg([
            'count', 'mean', 'std', 'min', 'max'
        ]).round(6)
        
        # Hourly statistics (diurnal cycle)
        hourly_stats = basin_stats.groupby('hour')['basin_mean'].agg([
            'count', 'mean', 'std', 'min', 'max'
        ]).round(6)
        
        # Forecast lead statistics
        lead_stats = basin_stats.groupby('forecast_lead')['basin_mean'].agg([
            'count', 'mean', 'std', 'min', 'max'
        ]).round(6)
        
        return overall_stats, monthly_stats, hourly_stats, lead_stats
    
    def generate_summary_report(self, overall_stats, monthly_stats, hourly_stats, lead_stats):
        """Generate a summary report"""
        report = f"""
HRRR Precipitation Analysis Summary
{self.basin_name} Basin
Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}

=== DATASET OVERVIEW ===
Total Forecasts: {overall_stats['total_forecasts']:,}
Date Range: {overall_stats['date_range_start']} to {overall_stats['date_range_end']}
Basin Coordinates: Lat({self.lat_min}, {self.lat_max}), Lon({self.lon_min}, {self.lon_max})

=== PRECIPITATION STATISTICS (Basin Average) ===
Mean: {overall_stats['mean_precipitation']:.4f} mm/hr
Standard Deviation: {overall_stats['std_precipitation']:.4f} mm/hr
Maximum: {overall_stats['max_precipitation']:.4f} mm/hr

Percentiles:
  5th:  {overall_stats['percentiles']['p05']:.4f} mm/hr
  25th: {overall_stats['percentiles']['p25']:.4f} mm/hr
  50th: {overall_stats['percentiles']['p50']:.4f} mm/hr
  75th: {overall_stats['percentiles']['p75']:.4f} mm/hr
  95th: {overall_stats['percentiles']['p95']:.4f} mm/hr

=== MONTHLY PATTERNS ===
{monthly_stats.to_string()}

=== DIURNAL PATTERNS ===
{hourly_stats.to_string()}

=== FORECAST LEAD PATTERNS ===
{lead_stats.to_string()}
"""
        return report
    
    def save_results(self, basin_stats, overall_stats, monthly_stats, hourly_stats, lead_stats):
        """Save all results to files"""
        logger.info("Saving results...")
        
        # Save basin statistics
        basin_stats_file = self.output_dir / "oso_creek_basin_precipitation_stats.csv"
        basin_stats.to_csv(basin_stats_file, index=False)
        logger.info(f"Saved basin statistics to {basin_stats_file}")
        
        # Save temporal statistics
        monthly_stats.to_csv(self.output_dir / "monthly_precipitation_stats.csv")
        hourly_stats.to_csv(self.output_dir / "hourly_precipitation_stats.csv")
        lead_stats.to_csv(self.output_dir / "forecast_lead_precipitation_stats.csv")
        
        # Save summary report
        report = self.generate_summary_report(overall_stats, monthly_stats, hourly_stats, lead_stats)
        report_file = self.output_dir / "precipitation_analysis_summary.txt"
        with open(report_file, 'w') as f:
            f.write(report)
        logger.info(f"Saved summary report to {report_file}")
        
        # Save overall statistics as JSON
        import json
        # Convert datetime objects to strings for JSON serialization
        json_stats = overall_stats.copy()
        json_stats['date_range_start'] = str(json_stats['date_range_start'])
        json_stats['date_range_end'] = str(json_stats['date_range_end'])
        
        stats_file = self.output_dir / "overall_precipitation_stats.json"
        with open(stats_file, 'w') as f:
            json.dump(json_stats, f, indent=2)
        logger.info(f"Saved overall statistics to {stats_file}")
    
    def run_analysis(self):
        """Run the complete analysis"""
        logger.info("Starting HRRR precipitation analysis...")
        
        try:
            # Load and preprocess data
            df = self.load_data()
            df = self.preprocess_data(df)
            
            # Compute basin statistics
            basin_stats = self.compute_basin_statistics(df)
            
            # Compute temporal statistics
            overall_stats, monthly_stats, hourly_stats, lead_stats = self.compute_temporal_statistics(basin_stats)
            
            # Save results
            self.save_results(basin_stats, overall_stats, monthly_stats, hourly_stats, lead_stats)
            
            logger.info("Analysis completed successfully!")
            
            # Print summary
            print("\n" + "="*60)
            print("ANALYSIS COMPLETE")
            print("="*60)
            print(f"Basin: {self.basin_name}")
            print(f"Total Forecasts Analyzed: {overall_stats['total_forecasts']:,}")
            print(f"Date Range: {overall_stats['date_range_start']} to {overall_stats['date_range_end']}")
            print(f"Mean Basin Precipitation: {overall_stats['mean_precipitation']:.4f} mm/hr")
            print(f"Results saved to: {self.output_dir}")
            print("="*60)
            
        except Exception as e:
            logger.error(f"Analysis failed: {e}")
            raise

def main():
    parser = argparse.ArgumentParser(description='Analyze HRRR precipitation data for Oso Creek basin')
    parser.add_argument('--data-dir', type=str, required=True,
                      help='Directory containing extracted HRRR CSV zip files')
    parser.add_argument('--output-dir', type=str, required=True,
                      help='Directory to save analysis results')
    
    args = parser.parse_args()
    
    analyzer = HRRRPrecipitationAnalyzer(args.data_dir, args.output_dir)
    analyzer.run_analysis()

if __name__ == "__main__":
    main()
