#!/usr/bin/env python3
"""
Advanced Cost Optimization Automation for AI Starter Kit
Implements intelligent cost reduction strategies for g4dn.xlarge GPU instances
Features: Spot instance management, auto-scaling, resource optimization, usage analytics
"""

import boto3
import json
import time
import logging
import requests
import schedule
from datetime import datetime, timedelta
from typing import Dict, List, Optional, Any
from dataclasses import dataclass
import os

# =============================================================================
# CONFIGURATION
# =============================================================================

@dataclass
class CostOptimizationConfig:
    region: str = "us-east-1"
    instance_type: str = "g4dn.xlarge"
    max_spot_price: float = 0.75
    target_utilization: float = 70.0
    scale_down_threshold: float = 20.0
    idle_timeout_minutes: int = 30
    cost_alert_threshold: float = 50.0  # Daily USD
    
config = CostOptimizationConfig()

# =============================================================================
# COST OPTIMIZATION MANAGER
# =============================================================================

class CostOptimizationManager:
    def __init__(self, config: CostOptimizationConfig):
        self.config = config
        self.logger = self._setup_logging()
        
        # AWS clients
        self.ec2 = boto3.client('ec2', region_name=config.region)
        self.autoscaling = boto3.client('autoscaling', region_name=config.region)
        self.cloudwatch = boto3.client('cloudwatch', region_name=config.region)
        self.pricing = boto3.client('pricing', region_name='us-east-1')  # Pricing API only in us-east-1
        self.sns = boto3.client('sns', region_name=config.region)
        
        # Get current instance info
        self.instance_id = self._get_instance_id()
        self.asg_name = self._get_asg_name()
        
    def _setup_logging(self) -> logging.Logger:
        logging.basicConfig(
            level=logging.INFO,
            format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
            handlers=[
                logging.FileHandler('/var/log/cost-optimization.log'),
                logging.StreamHandler()
            ]
        )
        return logging.getLogger('cost_optimizer')
    
    def _get_instance_id(self) -> str:
        try:
            response = requests.get(
                'http://169.254.169.254/latest/meta-data/instance-id',
                timeout=5
            )
            return response.text
        except:
            return "unknown"
    
    def _get_asg_name(self) -> Optional[str]:
        """Get Auto Scaling Group name for current instance"""
        try:
            response = self.autoscaling.describe_auto_scaling_instances(
                InstanceIds=[self.instance_id]
            )
            if response['AutoScalingInstances']:
                return response['AutoScalingInstances'][0]['AutoScalingGroupName']
        except Exception as e:
            self.logger.warning(f"Could not get ASG name: {e}")
        return None
    
    def get_current_spot_prices(self) -> Dict[str, float]:
        """Get current spot prices for GPU instances"""
        try:
            response = self.ec2.describe_spot_price_history(
                InstanceTypes=['g4dn.xlarge', 'g4dn.2xlarge', 'g4ad.xlarge', 'g5.xlarge'],
                ProductDescriptions=['Linux/UNIX'],
                StartTime=datetime.utcnow() - timedelta(hours=1),
                EndTime=datetime.utcnow()
            )
            
            current_prices = {}
            for price in response['SpotPriceHistory']:
                instance_type = price['InstanceType']
                if instance_type not in current_prices or price['Timestamp'] > current_prices[instance_type]['timestamp']:
                    current_prices[instance_type] = {
                        'price': float(price['SpotPrice']),
                        'timestamp': price['Timestamp'],
                        'az': price['AvailabilityZone']
                    }
            
            return current_prices
        except Exception as e:
            self.logger.error(f"Error getting spot prices: {e}")
            return {}
    
    def get_on_demand_prices(self) -> Dict[str, float]:
        """Get on-demand prices for comparison"""
        # These are approximate prices as of 2024 - should be updated regularly
        return {
            'g4dn.xlarge': 1.19,
            'g4dn.2xlarge': 2.38,
            'g4ad.xlarge': 0.95,
            'g5.xlarge': 1.21
        }
    
    def calculate_potential_savings(self) -> Dict[str, Any]:
        """Calculate potential cost savings from optimization strategies"""
        spot_prices = self.get_current_spot_prices()
        on_demand_prices = self.get_on_demand_prices()
        
        savings_analysis = {}
        
        for instance_type in spot_prices:
            if instance_type in on_demand_prices:
                spot_price = spot_prices[instance_type]['price']
                on_demand_price = on_demand_prices[instance_type]
                
                hourly_savings = on_demand_price - spot_price
                daily_savings = hourly_savings * 24
                monthly_savings = daily_savings * 30
                savings_percent = (hourly_savings / on_demand_price) * 100
                
                savings_analysis[instance_type] = {
                    'spot_price': spot_price,
                    'on_demand_price': on_demand_price,
                    'hourly_savings': hourly_savings,
                    'daily_savings': daily_savings,
                    'monthly_savings': monthly_savings,
                    'savings_percent': savings_percent
                }
        
        return savings_analysis
    
    def get_gpu_utilization(self) -> float:
        """Get current GPU utilization from CloudWatch"""
        try:
            end_time = datetime.utcnow()
            start_time = end_time - timedelta(minutes=10)
            
            response = self.cloudwatch.get_metric_statistics(
                Namespace='GPU/Monitoring',
                MetricName='GPUUtilization',
                Dimensions=[
                    {'Name': 'InstanceId', 'Value': self.instance_id}
                ],
                StartTime=start_time,
                EndTime=end_time,
                Period=300,
                Statistics=['Average']
            )
            
            if response['Datapoints']:
                return response['Datapoints'][-1]['Average']
            else:
                return 0.0
                
        except Exception as e:
            self.logger.error(f"Error getting GPU utilization: {e}")
            return 0.0
    
    def check_idle_instances(self) -> List[str]:
        """Check for idle instances that can be terminated"""
        idle_instances = []
        
        try:
            # Get instances in ASG
            if not self.asg_name:
                return idle_instances
            
            response = self.autoscaling.describe_auto_scaling_groups(
                AutoScalingGroupNames=[self.asg_name]
            )
            
            if not response['AutoScalingGroups']:
                return idle_instances
            
            instances = response['AutoScalingGroups'][0]['Instances']
            
            for instance in instances:
                instance_id = instance['InstanceId']
                
                # Check GPU utilization for each instance
                end_time = datetime.utcnow()
                start_time = end_time - timedelta(minutes=self.config.idle_timeout_minutes)
                
                response = self.cloudwatch.get_metric_statistics(
                    Namespace='GPU/Monitoring',
                    MetricName='GPUUtilization',
                    Dimensions=[
                        {'Name': 'InstanceId', 'Value': instance_id}
                    ],
                    StartTime=start_time,
                    EndTime=end_time,
                    Period=300,
                    Statistics=['Average']
                )
                
                if response['Datapoints']:
                    avg_utilization = sum(dp['Average'] for dp in response['Datapoints']) / len(response['Datapoints'])
                    if avg_utilization < self.config.scale_down_threshold:
                        idle_instances.append(instance_id)
                        self.logger.info(f"Instance {instance_id} is idle (avg utilization: {avg_utilization:.1f}%)")
                
        except Exception as e:
            self.logger.error(f"Error checking idle instances: {e}")
        
        return idle_instances
    
    def optimize_spot_instance_pricing(self):
        """Optimize spot instance pricing strategy"""
        self.logger.info("Optimizing spot instance pricing...")
        
        spot_prices = self.get_current_spot_prices()
        savings_analysis = self.calculate_potential_savings()
        
        # Find the most cost-effective instance type
        best_option = None
        best_savings = 0
        
        for instance_type, analysis in savings_analysis.items():
            if analysis['savings_percent'] > best_savings and analysis['spot_price'] <= self.config.max_spot_price:
                best_savings = analysis['savings_percent']
                best_option = instance_type
        
        if best_option:
            self.logger.info(f"Best spot instance option: {best_option} (${spot_prices[best_option]['price']:.3f}/hr, {best_savings:.1f}% savings)")
            
            # Update Auto Scaling Group launch template if needed
            if best_option != self.config.instance_type:
                self._update_asg_instance_type(best_option)
        
        # Log cost analysis
        for instance_type, analysis in savings_analysis.items():
            self.logger.info(f"{instance_type}: ${analysis['spot_price']:.3f}/hr spot vs ${analysis['on_demand_price']:.2f}/hr on-demand ({analysis['savings_percent']:.1f}% savings)")
    
    def _update_asg_instance_type(self, new_instance_type: str):
        """Update Auto Scaling Group with new instance type"""
        try:
            if not self.asg_name:
                self.logger.warning("No ASG found to update")
                return
            
            # This would require updating the launch template
            # Implementation depends on specific infrastructure setup
            self.logger.info(f"Would update ASG {self.asg_name} to use {new_instance_type}")
            
        except Exception as e:
            self.logger.error(f"Error updating ASG instance type: {e}")
    
    def implement_auto_scaling(self):
        """Implement intelligent auto-scaling based on GPU utilization"""
        self.logger.info("Checking auto-scaling requirements...")
        
        current_utilization = self.get_gpu_utilization()
        
        if not self.asg_name:
            self.logger.warning("No Auto Scaling Group found")
            return
        
        try:
            # Get current ASG configuration
            response = self.autoscaling.describe_auto_scaling_groups(
                AutoScalingGroupNames=[self.asg_name]
            )
            
            if not response['AutoScalingGroups']:
                return
            
            asg = response['AutoScalingGroups'][0]
            current_capacity = asg['DesiredCapacity']
            max_capacity = asg['MaxSize']
            min_capacity = asg['MinSize']
            
            self.logger.info(f"Current ASG capacity: {current_capacity}, GPU utilization: {current_utilization:.1f}%")
            
            # Scale up if utilization is high
            if current_utilization > self.config.target_utilization and current_capacity < max_capacity:
                new_capacity = min(current_capacity + 1, max_capacity)
                self.logger.info(f"Scaling up to {new_capacity} instances due to high GPU utilization")
                
                self.autoscaling.set_desired_capacity(
                    AutoScalingGroupName=self.asg_name,
                    DesiredCapacity=new_capacity
                )
            
            # Scale down if utilization is low
            elif current_utilization < self.config.scale_down_threshold and current_capacity > min_capacity:
                idle_instances = self.check_idle_instances()
                if len(idle_instances) > 0:
                    new_capacity = max(current_capacity - 1, min_capacity)
                    self.logger.info(f"Scaling down to {new_capacity} instances due to low GPU utilization")
                    
                    self.autoscaling.set_desired_capacity(
                        AutoScalingGroupName=self.asg_name,
                        DesiredCapacity=new_capacity
                    )
            
        except Exception as e:
            self.logger.error(f"Error in auto-scaling: {e}")
    
    def optimize_storage_costs(self):
        """Optimize EBS and EFS storage costs"""
        self.logger.info("Optimizing storage costs...")
        
        try:
            # Get EBS volumes for current instance
            response = self.ec2.describe_volumes(
                Filters=[
                    {'Name': 'attachment.instance-id', 'Values': [self.instance_id]}
                ]
            )
            
            for volume in response['Volumes']:
                volume_id = volume['VolumeId']
                volume_type = volume['VolumeType']
                size = volume['Size']
                iops = volume.get('Iops', 0)
                
                # Recommend gp3 if using gp2
                if volume_type == 'gp2':
                    self.logger.info(f"Volume {volume_id}: Consider migrating from gp2 to gp3 for cost savings")
                
                # Check for oversized volumes
                if size > 100:  # Arbitrary threshold
                    self.logger.info(f"Volume {volume_id}: Large volume ({size}GB) - monitor usage and consider resize")
        
        except Exception as e:
            self.logger.error(f"Error optimizing storage: {e}")
    
    def monitor_daily_costs(self) -> float:
        """Monitor and alert on daily costs"""
        try:
            # This is a simplified cost monitoring
            # In practice, would use AWS Cost Explorer API or billing APIs
            
            # Estimate current daily cost based on instance hours
            current_utilization = self.get_gpu_utilization()
            spot_prices = self.get_current_spot_prices()
            
            if self.config.instance_type in spot_prices:
                hourly_cost = spot_prices[self.config.instance_type]['price']
                estimated_daily_cost = hourly_cost * 24
                
                self.logger.info(f"Estimated daily cost: ${estimated_daily_cost:.2f}")
                
                if estimated_daily_cost > self.config.cost_alert_threshold:
                    self._send_cost_alert(estimated_daily_cost)
                
                return estimated_daily_cost
        
        except Exception as e:
            self.logger.error(f"Error monitoring costs: {e}")
        
        return 0.0
    
    def _send_cost_alert(self, daily_cost: float):
        """Send cost alert notification"""
        try:
            message = f"""
Cost Alert: AI Starter Kit

Daily cost estimate: ${daily_cost:.2f}
Threshold: ${self.config.cost_alert_threshold:.2f}
Instance: {self.instance_id}
Time: {datetime.now().isoformat()}

Consider:
1. Scaling down unused instances
2. Optimizing GPU utilization
3. Using more cost-effective instance types
4. Implementing scheduled shutdown for non-production workloads
"""
            
            # This would require setting up an SNS topic
            # self.sns.publish(TopicArn='arn:aws:sns:region:account:cost-alerts', Message=message)
            self.logger.warning(f"COST ALERT: Daily cost ${daily_cost:.2f} exceeds threshold ${self.config.cost_alert_threshold:.2f}")
            
        except Exception as e:
            self.logger.error(f"Error sending cost alert: {e}")
    
    def cleanup_unused_resources(self):
        """Clean up unused AWS resources to reduce costs"""
        self.logger.info("Cleaning up unused resources...")
        
        try:
            # Clean up old snapshots (keep last 7 days)
            cutoff_date = datetime.utcnow() - timedelta(days=7)
            
            response = self.ec2.describe_snapshots(OwnerIds=['self'])
            old_snapshots = [
                snap for snap in response['Snapshots']
                if snap['StartTime'].replace(tzinfo=None) < cutoff_date
            ]
            
            for snapshot in old_snapshots:
                # In practice, would add more checks before deletion
                self.logger.info(f"Old snapshot found: {snapshot['SnapshotId']} from {snapshot['StartTime']}")
                # self.ec2.delete_snapshot(SnapshotId=snapshot['SnapshotId'])
            
            # Clean up unattached volumes
            response = self.ec2.describe_volumes(
                Filters=[{'Name': 'status', 'Values': ['available']}]
            )
            
            for volume in response['Volumes']:
                self.logger.info(f"Unattached volume found: {volume['VolumeId']} ({volume['Size']}GB)")
                # Would add checks before deletion
        
        except Exception as e:
            self.logger.error(f"Error cleaning up resources: {e}")
    
    def generate_cost_report(self) -> Dict[str, Any]:
        """Generate comprehensive cost optimization report"""
        self.logger.info("Generating cost optimization report...")
        
        spot_prices = self.get_current_spot_prices()
        savings_analysis = self.calculate_potential_savings()
        current_utilization = self.get_gpu_utilization()
        estimated_daily_cost = self.monitor_daily_costs()
        
        report = {
            'timestamp': datetime.now().isoformat(),
            'instance_id': self.instance_id,
            'current_gpu_utilization': current_utilization,
            'estimated_daily_cost': estimated_daily_cost,
            'spot_prices': spot_prices,
            'savings_analysis': savings_analysis,
            'recommendations': []
        }
        
        # Generate recommendations
        if current_utilization < 30:
            report['recommendations'].append("Low GPU utilization detected - consider scaling down or optimizing workloads")
        
        if estimated_daily_cost > self.config.cost_alert_threshold:
            report['recommendations'].append(f"Daily cost ${estimated_daily_cost:.2f} exceeds threshold - review resource usage")
        
        best_instance = min(savings_analysis.items(), key=lambda x: x[1]['spot_price']) if savings_analysis else None
        if best_instance:
            instance_type, analysis = best_instance
            if analysis['savings_percent'] > 50:
                report['recommendations'].append(f"Consider {instance_type} for {analysis['savings_percent']:.1f}% cost savings")
        
        return report
    
    def run_optimization_cycle(self):
        """Run complete cost optimization cycle"""
        self.logger.info("Starting cost optimization cycle...")
        
        try:
            # 1. Check and optimize spot pricing
            self.optimize_spot_instance_pricing()
            
            # 2. Implement auto-scaling
            self.implement_auto_scaling()
            
            # 3. Optimize storage
            self.optimize_storage_costs()
            
            # 4. Monitor costs
            self.monitor_daily_costs()
            
            # 5. Clean up unused resources
            self.cleanup_unused_resources()
            
            # 6. Generate report
            report = self.generate_cost_report()
            
            # Save report
            with open(f'/var/log/cost-optimization-report-{datetime.now().strftime("%Y-%m-%d")}.json', 'w') as f:
                json.dump(report, f, indent=2)
            
            self.logger.info("Cost optimization cycle completed")
            
        except Exception as e:
            self.logger.error(f"Error in optimization cycle: {e}")

# =============================================================================
# SCHEDULING AND AUTOMATION
# =============================================================================

def setup_scheduled_optimization():
    """Set up scheduled cost optimization tasks"""
    optimizer = CostOptimizationManager(config)
    
    # Schedule different optimization tasks
    schedule.every(15).minutes.do(optimizer.implement_auto_scaling)
    schedule.every(1).hours.do(optimizer.optimize_spot_instance_pricing)
    schedule.every(6).hours.do(optimizer.cleanup_unused_resources)
    schedule.every(1).days.do(optimizer.generate_cost_report)
    
    logging.info("Scheduled cost optimization tasks configured")
    
    # Run scheduling loop
    while True:
        schedule.run_pending()
        time.sleep(60)

# =============================================================================
# CLI INTERFACE
# =============================================================================

def main():
    import argparse
    
    parser = argparse.ArgumentParser(description='AI Starter Kit Cost Optimization')
    parser.add_argument('--action', choices=['optimize', 'report', 'schedule'], 
                       default='optimize', help='Action to perform')
    parser.add_argument('--max-spot-price', type=float, default=0.75,
                       help='Maximum spot price to pay')
    parser.add_argument('--cost-threshold', type=float, default=50.0,
                       help='Daily cost alert threshold')
    
    args = parser.parse_args()
    
    # Update config from arguments
    config.max_spot_price = args.max_spot_price
    config.cost_alert_threshold = args.cost_threshold
    
    optimizer = CostOptimizationManager(config)
    
    if args.action == 'optimize':
        optimizer.run_optimization_cycle()
    elif args.action == 'report':
        report = optimizer.generate_cost_report()
        print(json.dumps(report, indent=2))
    elif args.action == 'schedule':
        setup_scheduled_optimization()

if __name__ == "__main__":
    main() 