#!/usr/bin/env python3
"""
Advanced Cost Optimization Lambda for AI Starter Kit
Features: Automated scaling, spot price monitoring, idle resource detection,
cost alerting, and intelligent resource management for GPU workloads
"""

import json
import boto3
import logging
from datetime import datetime, timedelta
from typing import Dict, List, Any
import os

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

class AIStarterKitCostOptimizer:
    def __init__(self):
        self.region = os.environ.get('AWS_REGION', 'us-east-1')
        
        # AWS clients
        self.ec2 = boto3.client('ec2', region_name=self.region)
        self.cloudwatch = boto3.client('cloudwatch', region_name=self.region)
        self.autoscaling = boto3.client('autoscaling', region_name=self.region)
        self.sns = boto3.client('sns', region_name=self.region)
        self.pricing = boto3.client('pricing', region_name='us-east-1')  # Pricing API only in us-east-1
        self.cost_explorer = boto3.client('ce', region_name='us-east-1')  # Cost Explorer only in us-east-1
        
        # Configuration
        self.project_tags = {
            'Project': 'AI-Starter-Kit',
            'Application': 'ai-starter-kit'
        }
        
        # Cost thresholds
        self.cost_thresholds = {
            'daily_warning': float(os.environ.get('DAILY_COST_WARNING', '50.0')),
            'daily_critical': float(os.environ.get('DAILY_COST_CRITICAL', '100.0')),
            'monthly_warning': float(os.environ.get('MONTHLY_COST_WARNING', '1000.0')),
            'monthly_critical': float(os.environ.get('MONTHLY_COST_CRITICAL', '2000.0'))
        }
        
        # SNS topic for alerts
        self.sns_topic_arn = os.environ.get('SNS_TOPIC_ARN')
        
        logger.info(f"Initialized Cost Optimizer for region {self.region}")
    
    def analyze_spot_price_trends(self) -> Dict[str, Any]:
        """Analyze spot price trends for GPU instances"""
        logger.info("Analyzing spot price trends...")
        
        instance_types = ['g4dn.xlarge', 'g4dn.2xlarge', 'g4dn.4xlarge', 'g4ad.xlarge', 'g5.xlarge']
        
        # Get availability zones
        az_response = self.ec2.describe_availability_zones()
        availability_zones = [az['ZoneName'] for az in az_response['AvailabilityZones']]
        
        price_analysis = {}
        
        for instance_type in instance_types:
            logger.info(f"Analyzing prices for {instance_type}")
            
            # Get spot price history for last 24 hours
            end_time = datetime.utcnow()
            start_time = end_time - timedelta(hours=24)
            
            try:
                response = self.ec2.describe_spot_price_history(
                    InstanceTypes=[instance_type],
                    ProductDescriptions=['Linux/UNIX'],
                    StartTime=start_time,
                    EndTime=end_time,
                    AvailabilityZones=availability_zones
                )
                
                prices_by_az = {}
                for price_info in response['SpotPriceHistory']:
                    az = price_info['AvailabilityZone']
                    price = float(price_info['SpotPrice'])
                    
                    if az not in prices_by_az:
                        prices_by_az[az] = []
                    prices_by_az[az].append(price)
                
                # Calculate statistics
                az_stats = {}
                for az, prices in prices_by_az.items():
                    if prices:
                        az_stats[az] = {
                            'current_price': prices[0],  # Most recent price
                            'avg_price': sum(prices) / len(prices),
                            'min_price': min(prices),
                            'max_price': max(prices),
                            'price_volatility': (max(prices) - min(prices)) / min(prices) if min(prices) > 0 else 0
                        }
                
                # Get on-demand price for comparison
                on_demand_price = self._get_on_demand_price(instance_type)
                
                price_analysis[instance_type] = {
                    'availability_zones': az_stats,
                    'on_demand_price': on_demand_price,
                    'best_az': min(az_stats.items(), key=lambda x: x[1]['current_price'])[0] if az_stats else None,
                    'max_savings_percent': 100 * (1 - min(az['current_price'] for az in az_stats.values()) / on_demand_price) if az_stats and on_demand_price > 0 else 0
                }
                
            except Exception as e:
                logger.error(f"Error analyzing prices for {instance_type}: {e}")
                price_analysis[instance_type] = {'error': str(e)}
        
        return price_analysis
    
    def _get_on_demand_price(self, instance_type: str) -> float:
        """Get on-demand price for instance type"""
        try:
            response = self.pricing.get_products(
                ServiceCode='AmazonEC2',
                Filters=[
                    {'Type': 'TERM_MATCH', 'Field': 'instanceType', 'Value': instance_type},
                    {'Type': 'TERM_MATCH', 'Field': 'location', 'Value': 'US East (N. Virginia)'},
                    {'Type': 'TERM_MATCH', 'Field': 'tenancy', 'Value': 'Shared'},
                    {'Type': 'TERM_MATCH', 'Field': 'operating-system', 'Value': 'Linux'},
                    {'Type': 'TERM_MATCH', 'Field': 'preInstalledSw', 'Value': 'NA'}
                ]
            )
            
            for price_item in response['PriceList']:
                price_data = json.loads(price_item)
                terms = price_data.get('terms', {}).get('OnDemand', {})
                
                for term_key, term_data in terms.items():
                    price_dimensions = term_data.get('priceDimensions', {})
                    for dim_key, dim_data in price_dimensions.items():
                        price_per_hour = dim_data.get('pricePerUnit', {}).get('USD', '0')
                        return float(price_per_hour)
            
        except Exception as e:
            logger.error(f"Error getting on-demand price for {instance_type}: {e}")
        
        return 0.0
    
    def check_idle_resources(self) -> List[Dict[str, Any]]:
        """Identify idle or underutilized resources"""
        logger.info("Checking for idle resources...")
        
        idle_resources = []
        
        # Get running instances with project tags
        instances_response = self.ec2.describe_instances(
            Filters=[
                {'Name': 'instance-state-name', 'Values': ['running']},
                {'Name': 'tag:Project', 'Values': ['AI-Starter-Kit']}
            ]
        )
        
        for reservation in instances_response['Reservations']:
            for instance in reservation['Instances']:
                instance_id = instance['InstanceId']
                instance_type = instance['InstanceType']
                launch_time = instance['LaunchTime']
                
                # Check GPU utilization from CloudWatch
                gpu_metrics = self._get_instance_metrics(instance_id, hours=2)
                
                # Determine if instance is idle
                is_idle = self._is_instance_idle(gpu_metrics, instance_id)
                
                if is_idle:
                    # Calculate runtime cost
                    runtime_hours = (datetime.utcnow().replace(tzinfo=None) - launch_time.replace(tzinfo=None)).total_seconds() / 3600
                    estimated_cost = self._calculate_instance_cost(instance_type, runtime_hours)
                    
                    idle_resources.append({
                        'instance_id': instance_id,
                        'instance_type': instance_type,
                        'launch_time': launch_time.isoformat(),
                        'runtime_hours': round(runtime_hours, 2),
                        'estimated_cost': round(estimated_cost, 2),
                        'reason': 'Low GPU utilization',
                        'recommendation': 'Consider terminating or investigating workload issues'
                    })
        
        return idle_resources
    
    def _get_instance_metrics(self, instance_id: str, hours: int = 1) -> Dict[str, List]:
        """Get CloudWatch metrics for an instance"""
        end_time = datetime.utcnow()
        start_time = end_time - timedelta(hours=hours)
        
        metrics = {}
        
        # GPU utilization metrics
        metric_queries = [
            {'name': 'GPUUtilization', 'namespace': 'GPU/AI-Starter-Kit'},
            {'name': 'GPUMemoryUtilization', 'namespace': 'GPU/AI-Starter-Kit'},
            {'name': 'CPUUtilization', 'namespace': 'AWS/EC2'}
        ]
        
        for query in metric_queries:
            try:
                response = self.cloudwatch.get_metric_statistics(
                    Namespace=query['namespace'],
                    MetricName=query['name'],
                    Dimensions=[
                        {'Name': 'InstanceId', 'Value': instance_id}
                    ],
                    StartTime=start_time,
                    EndTime=end_time,
                    Period=300,  # 5 minutes
                    Statistics=['Average']
                )
                
                metrics[query['name']] = [
                    point['Average'] for point in 
                    sorted(response['Datapoints'], key=lambda x: x['Timestamp'])
                ]
                
            except Exception as e:
                logger.error(f"Error getting {query['name']} for {instance_id}: {e}")
                metrics[query['name']] = []
        
        return metrics
    
    def _is_instance_idle(self, metrics: Dict[str, List], instance_id: str) -> bool:
        """Determine if an instance is idle based on metrics"""
        # Check GPU utilization
        gpu_util = metrics.get('GPUUtilization', [])
        gpu_memory = metrics.get('GPUMemoryUtilization', [])
        cpu_util = metrics.get('CPUUtilization', [])
        
        # Instance is idle if:
        # 1. GPU utilization < 5% for the past hour
        # 2. GPU memory utilization < 10% for the past hour
        # 3. CPU utilization < 10% for the past hour
        
        if gpu_util and len(gpu_util) > 0:
            avg_gpu_util = sum(gpu_util) / len(gpu_util)
            if avg_gpu_util >= 5.0:
                return False
        
        if gpu_memory and len(gpu_memory) > 0:
            avg_gpu_memory = sum(gpu_memory) / len(gpu_memory)
            if avg_gpu_memory >= 10.0:
                return False
        
        if cpu_util and len(cpu_util) > 0:
            avg_cpu_util = sum(cpu_util) / len(cpu_util)
            if avg_cpu_util >= 10.0:
                return False
        
        # If we have no metrics, don't consider it idle (might be starting up)
        if not any([gpu_util, gpu_memory, cpu_util]):
            return False
        
        return True
    
    def _calculate_instance_cost(self, instance_type: str, runtime_hours: float) -> float:
        """Calculate estimated cost for instance runtime"""
        # Simplified cost calculation based on typical spot prices
        hourly_rates = {
            'g4dn.xlarge': 0.35,   # Typical spot price
            'g4dn.2xlarge': 0.70,
            'g4dn.4xlarge': 1.40,
            'g4ad.xlarge': 0.30,
            'g5.xlarge': 0.40
        }
        
        hourly_rate = hourly_rates.get(instance_type, 0.50)  # Default rate
        return hourly_rate * runtime_hours
    
    def get_cost_insights(self) -> Dict[str, Any]:
        """Get comprehensive cost insights"""
        logger.info("Generating cost insights...")
        
        # Get current month costs
        end_date = datetime.utcnow().strftime('%Y-%m-%d')
        start_date = datetime.utcnow().replace(day=1).strftime('%Y-%m-%d')
        
        try:
            cost_response = self.cost_explorer.get_cost_and_usage(
                TimePeriod={
                    'Start': start_date,
                    'End': end_date
                },
                Granularity='MONTHLY',
                Metrics=['BlendedCost'],
                GroupBy=[
                    {'Type': 'DIMENSION', 'Key': 'SERVICE'},
                    {'Type': 'TAG', 'Key': 'Project'}
                ],
                Filter={
                    'Tags': {
                        'Key': 'Project',
                        'Values': ['AI-Starter-Kit']
                    }
                }
            )
            
            total_cost = 0.0
            service_costs = {}
            
            for result in cost_response['ResultsByTime']:
                for group in result['Groups']:
                    service = group['Keys'][0] if group['Keys'] else 'Unknown'
                    cost = float(group['Metrics']['BlendedCost']['Amount'])
                    total_cost += cost
                    service_costs[service] = service_costs.get(service, 0) + cost
            
            # Get forecasted costs
            forecast_response = self.cost_explorer.get_cost_forecast(
                TimePeriod={
                    'Start': end_date,
                    'End': (datetime.utcnow() + timedelta(days=30)).strftime('%Y-%m-%d')
                },
                Metric='BLENDED_COST',
                Granularity='MONTHLY',
                Filter={
                    'Tags': {
                        'Key': 'Project',
                        'Values': ['AI-Starter-Kit']
                    }
                }
            )
            
            forecasted_cost = float(forecast_response['Total']['Amount'])
            
            insights = {
                'current_month_cost': round(total_cost, 2),
                'forecasted_month_cost': round(forecasted_cost, 2),
                'service_breakdown': {k: round(v, 2) for k, v in service_costs.items()},
                'cost_trend': 'increasing' if forecasted_cost > total_cost else 'stable',
                'savings_opportunities': []
            }
            
            # Add savings recommendations
            if total_cost > self.cost_thresholds['monthly_warning']:
                insights['savings_opportunities'].append({
                    'type': 'cost_alert',
                    'message': f"Monthly costs (${total_cost:.2f}) exceed warning threshold",
                    'action': 'Review resource usage and consider scaling down'
                })
            
            return insights
            
        except Exception as e:
            logger.error(f"Error getting cost insights: {e}")
            return {'error': str(e)}
    
    def optimize_auto_scaling(self) -> Dict[str, Any]:
        """Optimize auto scaling group configurations"""
        logger.info("Optimizing auto scaling configurations...")
        
        optimizations = []
        
        try:
            # Get auto scaling groups with project tags
            asg_response = self.autoscaling.describe_auto_scaling_groups()
            
            for asg in asg_response['AutoScalingGroups']:
                asg_name = asg['AutoScalingGroupName']
                
                # Check if this is our AI Starter Kit ASG
                is_ai_starter_kit = False
                for tag in asg.get('Tags', []):
                    if tag.get('Key') == 'Project' and tag.get('Value') == 'AI-Starter-Kit':
                        is_ai_starter_kit = True
                        break
                
                if not is_ai_starter_kit:
                    continue
                
                # Analyze scaling metrics
                current_capacity = asg['DesiredCapacity']
                min_size = asg['MinSize']
                max_size = asg['MaxSize']
                
                # Get recent scaling activities
                activity_response = self.autoscaling.describe_scaling_activities(
                    AutoScalingGroupName=asg_name,
                    MaxRecords=20
                )
                
                # Analyze scaling patterns
                recent_scale_ups = 0
                recent_scale_downs = 0
                
                for activity in activity_response['Activities']:
                    if 'scale up' in activity.get('Description', '').lower():
                        recent_scale_ups += 1
                    elif 'scale down' in activity.get('Description', '').lower():
                        recent_scale_downs += 1
                
                # Generate optimization recommendations
                recommendations = []
                
                if recent_scale_ups == 0 and current_capacity > min_size:
                    recommendations.append({
                        'type': 'reduce_capacity',
                        'current': current_capacity,
                        'recommended': max(min_size, current_capacity - 1),
                        'reason': 'No recent scale-up activity detected'
                    })
                
                if recent_scale_ups > recent_scale_downs and max_size < 10:
                    recommendations.append({
                        'type': 'increase_max_capacity',
                        'current': max_size,
                        'recommended': min(10, max_size + 2),
                        'reason': 'Frequent scale-up activity suggests need for higher capacity'
                    })
                
                optimizations.append({
                    'asg_name': asg_name,
                    'current_config': {
                        'desired': current_capacity,
                        'min': min_size,
                        'max': max_size
                    },
                    'recent_activities': {
                        'scale_ups': recent_scale_ups,
                        'scale_downs': recent_scale_downs
                    },
                    'recommendations': recommendations
                })
        
        except Exception as e:
            logger.error(f"Error optimizing auto scaling: {e}")
            return {'error': str(e)}
        
        return {'optimizations': optimizations}
    
    def send_cost_alert(self, alert_data: Dict[str, Any]) -> bool:
        """Send cost alert via SNS"""
        if not self.sns_topic_arn:
            logger.warning("No SNS topic configured for alerts")
            return False
        
        try:
            message = {
                'alert_type': 'cost_optimization',
                'timestamp': datetime.utcnow().isoformat(),
                'data': alert_data
            }
            
            self.sns.publish(
                TopicArn=self.sns_topic_arn,
                Subject=f"AI Starter Kit Cost Alert - {alert_data.get('type', 'General')}",
                Message=json.dumps(message, indent=2, default=str)
            )
            
            logger.info("Cost alert sent successfully")
            return True
            
        except Exception as e:
            logger.error(f"Error sending cost alert: {e}")
            return False
    
    def generate_comprehensive_report(self) -> Dict[str, Any]:
        """Generate comprehensive cost optimization report"""
        logger.info("Generating comprehensive cost optimization report...")
        
        report = {
            'timestamp': datetime.utcnow().isoformat(),
            'region': self.region,
            'spot_price_analysis': self.analyze_spot_price_trends(),
            'idle_resources': self.check_idle_resources(),
            'cost_insights': self.get_cost_insights(),
            'scaling_optimizations': self.optimize_auto_scaling(),
            'recommendations': []
        }
        
        # Generate high-level recommendations
        recommendations = []
        
        # Spot price recommendations
        spot_analysis = report['spot_price_analysis']
        for instance_type, data in spot_analysis.items():
            if isinstance(data, dict) and 'max_savings_percent' in data:
                if data['max_savings_percent'] > 60:
                    recommendations.append({
                        'type': 'spot_savings',
                        'priority': 'high',
                        'message': f"Excellent spot savings available for {instance_type}: {data['max_savings_percent']:.1f}%",
                        'action': f"Deploy in {data['best_az']} for maximum savings"
                    })
        
        # Idle resource recommendations
        idle_resources = report['idle_resources']
        if idle_resources:
            total_idle_cost = sum(resource['estimated_cost'] for resource in idle_resources)
            recommendations.append({
                'type': 'idle_resources',
                'priority': 'medium',
                'message': f"Found {len(idle_resources)} idle resources costing ${total_idle_cost:.2f}",
                'action': 'Review and terminate unused instances'
            })
        
        # Cost threshold recommendations
        cost_insights = report['cost_insights']
        if isinstance(cost_insights, dict) and 'current_month_cost' in cost_insights:
            current_cost = cost_insights['current_month_cost']
            if current_cost > self.cost_thresholds['monthly_critical']:
                recommendations.append({
                    'type': 'cost_alert',
                    'priority': 'critical',
                    'message': f"Monthly costs (${current_cost:.2f}) exceed critical threshold",
                    'action': 'Immediate review and cost reduction required'
                })
            elif current_cost > self.cost_thresholds['monthly_warning']:
                recommendations.append({
                    'type': 'cost_alert',
                    'priority': 'warning',
                    'message': f"Monthly costs (${current_cost:.2f}) exceed warning threshold",
                    'action': 'Monitor usage and consider optimization'
                })
        
        report['recommendations'] = recommendations
        
        # Send alerts for critical issues
        critical_recommendations = [r for r in recommendations if r['priority'] == 'critical']
        if critical_recommendations:
            self.send_cost_alert({
                'type': 'critical_cost_alert',
                'recommendations': critical_recommendations,
                'total_monthly_cost': cost_insights.get('current_month_cost', 0)
            })
        
        return report

def lambda_handler(event, context):
    """AWS Lambda entry point"""
    try:
        optimizer = AIStarterKitCostOptimizer()
        
        # Check what action to perform
        action = event.get('action', 'comprehensive_report')
        
        if action == 'spot_analysis':
            result = optimizer.analyze_spot_price_trends()
        elif action == 'idle_check':
            result = optimizer.check_idle_resources()
        elif action == 'cost_insights':
            result = optimizer.get_cost_insights()
        elif action == 'scaling_optimization':
            result = optimizer.optimize_auto_scaling()
        else:
            result = optimizer.generate_comprehensive_report()
        
        return {
            'statusCode': 200,
            'body': json.dumps(result, default=str, indent=2)
        }
        
    except Exception as e:
        logger.error(f"Lambda execution error: {e}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

# For testing locally
if __name__ == "__main__":
    # Test the optimizer
    optimizer = AIStarterKitCostOptimizer()
    report = optimizer.generate_comprehensive_report()
    print(json.dumps(report, indent=2, default=str)) 