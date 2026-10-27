import dataiku
import pandas as pd
from flask import jsonify, request
import datetime
import pytz

@app.route("/data")
def data_endpoint():
    try:
        client = dataiku.api_client()
        project = client.get_default_project()
        project_name = project.project_key
        
        requested_date = request.args.get('date')
        if not requested_date:
            tz = pytz.timezone('Asia/Jakarta')
            requested_date = datetime.datetime.now(tz).strftime('%Y-%m-%d')
            
        runs_summary = []
        
        
        global_stats = {
            "total": 0, "success": 0, "failed": 0, "running": 0,
            "sum_duration": 0, "count_duration": 0
        }
        
        status_mapping = {
            'DONE': 'SUCCESS', 'SUCCESS': 'SUCCESS',
            'FAILED': 'FAILED', 'ABORTED': 'FAILED',
            'RUNNING': 'RUNNING', 'WAITING': 'RUNNING'
        }
        
    
        jobs = project.list_jobs()
        for job in jobs:
            job_id = job.get('def', {}).get('id', 'unknown')
            job_name = job.get('def', {}).get('name', job_id)
            
            start_time = job.get('startTime') or job.get('baseStatus', {}).get('startTime')
            end_time = job.get('endTime') or job.get('baseStatus', {}).get('endTime')
            state = job.get('state') or job.get('baseStatus', {}).get('state', 'UNKNOWN')
            overall_status = status_mapping.get(state, state)
            
            total_duration = (end_time - start_time) / 1000.0 if start_time and end_time else 0
            
          
            global_stats["total"] += 1
            if overall_status == 'SUCCESS': global_stats["success"] += 1
            elif overall_status == 'FAILED': global_stats["failed"] += 1
            elif overall_status == 'RUNNING': global_stats["running"] += 1
            
            if total_duration > 0:
                global_stats["sum_duration"] += total_duration
                global_stats["count_duration"] += 1
            
            
            if not start_time:
                continue
                
           
            job_date_str = pd.to_datetime(start_time, unit='ms', utc=True).tz_convert('Asia/Jakarta').strftime('%Y-%m-%d')
            if job_date_str != requested_date:
                continue
                
            start_iso = pd.to_datetime(start_time, unit='ms', utc=True).isoformat() if start_time else None
            end_iso = pd.to_datetime(end_time, unit='ms', utc=True).isoformat() if end_time else None
            
            runs_summary.append({
                "TYPE": "JOB",
                "PROJECT_NAME": project_name,
                "SCENARIO_NAME": job_name,
                "RUN_ID": f"{project_name}::JOB::{job_id}",
                "run_start": start_iso,
                "run_end": end_iso,
                "total_duration": total_duration,
                "overall_status": overall_status,
            })

        
        scenarios = project.list_scenarios()
        for scenario in scenarios:
            scenario_id = scenario['id']
            scenario_name = scenario.get('name', scenario_id)
            scen = project.get_scenario(scenario_id)
            
            try:
                recent_runs = scen.get_light_runs(limit=50)
            except:
                continue
                
            for run_info in recent_runs:
                run_id = run_info.get('runId', 'unknown')
                start_time = run_info.get('start')
                end_time = run_info.get('end')
                state = run_info.get('result', {}).get('outcome', 'UNKNOWN')
                overall_status = status_mapping.get(state, state)
                total_duration = (end_time - start_time) / 1000.0 if start_time and end_time else 0
                
            
                global_stats["total"] += 1
                if overall_status == 'SUCCESS': global_stats["success"] += 1
                elif overall_status == 'FAILED': global_stats["failed"] += 1
                elif overall_status == 'RUNNING': global_stats["running"] += 1
                
                if total_duration > 0:
                    global_stats["sum_duration"] += total_duration
                    global_stats["count_duration"] += 1
                # ----------------------------------------------
                
                if not start_time:
                    continue
                    
                scen_date_str = pd.to_datetime(start_time, unit='ms', utc=True).tz_convert('Asia/Jakarta').strftime('%Y-%m-%d')
                if scen_date_str != requested_date:
                    continue
                    
                start_iso = pd.to_datetime(start_time, unit='ms', utc=True).isoformat() if start_time else None
                end_iso = pd.to_datetime(end_time, unit='ms', utc=True).isoformat() if end_time else None
                
                runs_summary.append({
                    "TYPE": "SCENARIO",
                    "PROJECT_NAME": project_name,
                    "SCENARIO_NAME": scenario_name,
                    "RUN_ID": f"{project_name}::SCEN::{scenario_id}::{run_id}",
                    "run_start": start_iso,
                    "run_end": end_iso,
                    "total_duration": total_duration,
                    "overall_status": overall_status,
                })

        runs_summary.sort(key=lambda x: x['run_start'] if x['run_start'] else '', reverse=True)

        return jsonify({
            "runs": runs_summary,
            "global_stats": global_stats, 
            "generated_at": pd.Timestamp.utcnow().isoformat()
        })
        
    except Exception as e:
        return jsonify({"error": str(e)})