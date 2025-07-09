-- Enhanced Agentic Multi-Agent Workforce Database Schema
-- PostgreSQL Database Schema for n8n AI Agent Workforce

-- =================================================================
-- AGENT REGISTRY TABLE
-- Implements MEMBER AWARENESS principle
-- =================================================================
CREATE TABLE IF NOT EXISTS agent_registry (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    agent_id VARCHAR(50) UNIQUE NOT NULL,
    agent_name VARCHAR(100) NOT NULL,
    authority_level INTEGER NOT NULL CHECK (authority_level BETWEEN 1 AND 5),
    capabilities JSONB NOT NULL DEFAULT '[]',
    specializations JSONB NOT NULL DEFAULT '[]',
    status VARCHAR(20) DEFAULT 'active' CHECK (status IN ('active', 'inactive', 'degraded', 'failed')),
    max_capacity INTEGER DEFAULT 5,
    current_load INTEGER DEFAULT 0,
    last_heartbeat TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    endpoint_url VARCHAR(255) NOT NULL,
    response_time_avg DECIMAL(8,2) DEFAULT 0,
    success_rate DECIMAL(5,2) DEFAULT 100.0,
    error_count INTEGER DEFAULT 0,
    total_requests INTEGER DEFAULT 0,
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- =================================================================
-- TASK QUEUE TABLE
-- Implements MEMBER SOLIDARITY and MEMBER AUTONOMY principles
-- =================================================================
CREATE TABLE IF NOT EXISTS task_queue (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    task_id VARCHAR(100) UNIQUE NOT NULL,
    workflow_id VARCHAR(100) NOT NULL,
    execution_id VARCHAR(100) NOT NULL,
    parent_task_id VARCHAR(100),
    agent VARCHAR(50) NOT NULL,
    action VARCHAR(100) NOT NULL,
    priority VARCHAR(10) DEFAULT 'medium' CHECK (priority IN ('high', 'medium', 'low')),
    status VARCHAR(20) DEFAULT 'pending' CHECK (status IN ('pending', 'assigned', 'in_progress', 'completed', 'failed', 'cancelled')),
    dependencies JSONB DEFAULT '[]',
    fallback_agent VARCHAR(50),
    timeout INTEGER DEFAULT 300,
    retry_count INTEGER DEFAULT 0,
    max_retries INTEGER DEFAULT 3,
    context JSONB DEFAULT '{}',
    result JSONB DEFAULT '{}',
    error_message TEXT,
    quality_score DECIMAL(3,2),
    duration INTEGER,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    assigned_at TIMESTAMP WITH TIME ZONE,
    started_at TIMESTAMP WITH TIME ZONE,
    completed_at TIMESTAMP WITH TIME ZONE,
    failed_at TIMESTAMP WITH TIME ZONE,
    
    CONSTRAINT fk_agent FOREIGN KEY (agent) REFERENCES agent_registry(agent_id),
    CONSTRAINT fk_fallback_agent FOREIGN KEY (fallback_agent) REFERENCES agent_registry(agent_id)
);

-- =================================================================
-- COMMUNICATION LOG TABLE
-- Implements MEMBER SOLIDARITY principle
-- =================================================================
CREATE TABLE IF NOT EXISTS communication_log (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    message_id VARCHAR(100) UNIQUE NOT NULL,
    task_id VARCHAR(100),
    sender VARCHAR(50) NOT NULL,
    recipient VARCHAR(50) NOT NULL,
    message_type VARCHAR(20) DEFAULT 'request' CHECK (message_type IN ('request', 'response', 'broadcast', 'error', 'heartbeat')),
    priority VARCHAR(10) DEFAULT 'medium' CHECK (priority IN ('high', 'medium', 'low')),
    content JSONB NOT NULL,
    metadata JSONB DEFAULT '{}',
    status VARCHAR(20) DEFAULT 'sent' CHECK (status IN ('sent', 'delivered', 'failed', 'timeout')),
    retry_count INTEGER DEFAULT 0,
    correlation_id VARCHAR(100),
    session_id VARCHAR(100),
    response_time INTEGER,
    timestamp TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    CONSTRAINT fk_sender FOREIGN KEY (sender) REFERENCES agent_registry(agent_id),
    CONSTRAINT fk_recipient FOREIGN KEY (recipient) REFERENCES agent_registry(agent_id)
);

-- =================================================================
-- WORKFLOW STATE TABLE
-- Implements MEMBER AWARENESS principle
-- =================================================================
CREATE TABLE IF NOT EXISTS workflow_state (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workflow_id VARCHAR(100) NOT NULL,
    execution_id VARCHAR(100) UNIQUE NOT NULL,
    state VARCHAR(20) DEFAULT 'running' CHECK (state IN ('running', 'completed', 'failed', 'cancelled')),
    progress DECIMAL(5,2) DEFAULT 0.0,
    total_tasks INTEGER DEFAULT 0,
    completed_tasks INTEGER DEFAULT 0,
    failed_tasks INTEGER DEFAULT 0,
    agents_involved JSONB DEFAULT '[]',
    start_time TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    end_time TIMESTAMP WITH TIME ZONE,
    duration INTEGER,
    context JSONB DEFAULT '{}',
    result JSONB DEFAULT '{}',
    error_message TEXT,
    quality_score DECIMAL(3,2),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- =================================================================
-- AGENT PERFORMANCE TABLE
-- Implements MEMBER RESILIENCY and MEMBER AWARENESS principles
-- =================================================================
CREATE TABLE IF NOT EXISTS agent_performance (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    agent_id VARCHAR(50) NOT NULL,
    metric_type VARCHAR(50) NOT NULL,
    metric_value DECIMAL(10,4) NOT NULL,
    measurement_time TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    context JSONB DEFAULT '{}',
    
    CONSTRAINT fk_agent_perf FOREIGN KEY (agent_id) REFERENCES agent_registry(agent_id)
);

-- =================================================================
-- SYSTEM HEALTH TABLE
-- Implements MEMBER RESILIENCY principle
-- =================================================================
CREATE TABLE IF NOT EXISTS system_health (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    component VARCHAR(50) NOT NULL,
    status VARCHAR(20) NOT NULL CHECK (status IN ('healthy', 'degraded', 'failed')),
    health_score DECIMAL(3,2) DEFAULT 100.0,
    last_check TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    error_count INTEGER DEFAULT 0,
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- =================================================================
-- KNOWLEDGE BASE TABLE
-- Implements MEMBER SOLIDARITY principle
-- =================================================================
CREATE TABLE IF NOT EXISTS knowledge_base (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    knowledge_id VARCHAR(100) UNIQUE NOT NULL,
    category VARCHAR(50) NOT NULL,
    title VARCHAR(200) NOT NULL,
    content TEXT NOT NULL,
    tags JSONB DEFAULT '[]',
    source_agent VARCHAR(50),
    confidence_score DECIMAL(3,2) DEFAULT 0.8,
    usage_count INTEGER DEFAULT 0,
    quality_rating DECIMAL(3,2) DEFAULT 0.0,
    vector_id VARCHAR(100), -- Reference to Qdrant vector
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    expires_at TIMESTAMP WITH TIME ZONE,
    
    CONSTRAINT fk_source_agent FOREIGN KEY (source_agent) REFERENCES agent_registry(agent_id)
);

-- =================================================================
-- DEPENDENCY GRAPH TABLE
-- Implements MEMBER EXPANDABILITY principle
-- =================================================================
CREATE TABLE IF NOT EXISTS dependency_graph (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    parent_task_id VARCHAR(100) NOT NULL,
    child_task_id VARCHAR(100) NOT NULL,
    dependency_type VARCHAR(20) DEFAULT 'requires' CHECK (dependency_type IN ('requires', 'blocks', 'enhances')),
    strength DECIMAL(3,2) DEFAULT 1.0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    CONSTRAINT fk_parent_task FOREIGN KEY (parent_task_id) REFERENCES task_queue(task_id),
    CONSTRAINT fk_child_task FOREIGN KEY (child_task_id) REFERENCES task_queue(task_id),
    CONSTRAINT unique_dependency UNIQUE (parent_task_id, child_task_id)
);

-- =================================================================
-- INDEXES FOR PERFORMANCE
-- =================================================================
CREATE INDEX idx_agent_registry_status ON agent_registry(status);
CREATE INDEX idx_agent_registry_capabilities ON agent_registry USING GIN(capabilities);
CREATE INDEX idx_task_queue_status ON task_queue(status);
CREATE INDEX idx_task_queue_priority ON task_queue(priority);
CREATE INDEX idx_task_queue_agent ON task_queue(agent);
CREATE INDEX idx_task_queue_created_at ON task_queue(created_at);
CREATE INDEX idx_communication_log_sender ON communication_log(sender);
CREATE INDEX idx_communication_log_recipient ON communication_log(recipient);
CREATE INDEX idx_communication_log_timestamp ON communication_log(timestamp);
CREATE INDEX idx_workflow_state_execution_id ON workflow_state(execution_id);
CREATE INDEX idx_agent_performance_agent_id ON agent_performance(agent_id);
CREATE INDEX idx_agent_performance_metric_type ON agent_performance(metric_type);
CREATE INDEX idx_system_health_component ON system_health(component);
CREATE INDEX idx_knowledge_base_category ON knowledge_base(category);
CREATE INDEX idx_knowledge_base_tags ON knowledge_base USING GIN(tags);

-- =================================================================
-- TRIGGERS FOR AUTOMATED UPDATES
-- =================================================================

-- Update agent registry statistics
CREATE OR REPLACE FUNCTION update_agent_stats()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'UPDATE' AND OLD.status != NEW.status THEN
        UPDATE agent_registry 
        SET updated_at = NOW()
        WHERE agent_id = NEW.agent;
    END IF;
    
    IF NEW.status = 'completed' THEN
        UPDATE agent_registry 
        SET 
            total_requests = total_requests + 1,
            success_rate = (
                SELECT (COUNT(*) FILTER (WHERE status = 'completed')::DECIMAL / COUNT(*)) * 100
                FROM task_queue 
                WHERE agent = NEW.agent
            ),
            current_load = current_load - 1
        WHERE agent_id = NEW.agent;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_agent_stats
    AFTER UPDATE ON task_queue
    FOR EACH ROW
    EXECUTE FUNCTION update_agent_stats();

-- Update workflow progress
CREATE OR REPLACE FUNCTION update_workflow_progress()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE workflow_state 
    SET 
        completed_tasks = (
            SELECT COUNT(*) 
            FROM task_queue 
            WHERE execution_id = NEW.execution_id AND status = 'completed'
        ),
        failed_tasks = (
            SELECT COUNT(*) 
            FROM task_queue 
            WHERE execution_id = NEW.execution_id AND status = 'failed'
        ),
        progress = (
            SELECT (COUNT(*) FILTER (WHERE status IN ('completed', 'failed'))::DECIMAL / COUNT(*)) * 100
            FROM task_queue 
            WHERE execution_id = NEW.execution_id
        ),
        updated_at = NOW()
    WHERE execution_id = NEW.execution_id;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_workflow_progress
    AFTER UPDATE ON task_queue
    FOR EACH ROW
    EXECUTE FUNCTION update_workflow_progress();

-- =================================================================
-- INITIAL DATA SEEDING
-- =================================================================

-- Insert initial agent registry data
INSERT INTO agent_registry (agent_id, agent_name, authority_level, capabilities, specializations, endpoint_url) VALUES
('hnic', 'The HNIC', 1, '["orchestration", "decision_making", "conflict_resolution", "strategic_planning"]', '["leadership", "coordination", "quality_assurance"]', 'http://n8n.geuse.io/webhook/workforce/hnic'),
('naiz', 'The Naiz', 2, '["project_management", "process_optimization", "quality_assurance", "team_coordination"]', '["agile_methodology", "performance_monitoring", "resource_allocation"]', 'http://n8n.geuse.io/webhook/a2a/naiz'),
('archivist', 'The Archivist', 3, '["historical_analysis", "pattern_recognition", "data_correlation", "research"]', '["historical_context", "trend_analysis", "precedent_identification"]', 'http://n8n.geuse.io/webhook/a2a/archivist'),
('voice', 'The Voice', 3, '["sentiment_analysis", "public_opinion", "emotional_intelligence", "communication_assessment"]', '["sentiment_tracking", "emotional_analysis", "public_perception"]', 'http://n8n.geuse.io/webhook/a2a/voice'),
('bag', 'The BAG', 3, '["financial_analysis", "legal_compliance", "risk_assessment", "business_advisory"]', '["finance", "legal", "compliance", "risk_management"]', 'http://n8n.geuse.io/webhook/a2a/bag'),
('pen', 'The Pen', 3, '["content_creation", "synthesis", "communication", "writing"]', '["writing", "editing", "content_strategy", "brand_voice"]', 'http://n8n.geuse.io/webhook/a2a/pen'),
('ear', 'The Ear', 4, '["current_events", "information_gathering", "trend_analysis", "monitoring"]', '["news_monitoring", "social_media_analysis", "trend_detection"]', 'http://n8n.geuse.io/webhook/a2a/ear')
ON CONFLICT (agent_id) DO UPDATE SET
    agent_name = EXCLUDED.agent_name,
    authority_level = EXCLUDED.authority_level,
    capabilities = EXCLUDED.capabilities,
    specializations = EXCLUDED.specializations,
    endpoint_url = EXCLUDED.endpoint_url,
    updated_at = NOW();

-- Insert initial system health monitoring
INSERT INTO system_health (component, status, health_score) VALUES
('postgresql', 'healthy', 100.0),
('qdrant', 'healthy', 100.0),
('n8n', 'healthy', 100.0),
('agent_registry', 'healthy', 100.0),
('task_queue', 'healthy', 100.0),
('communication_system', 'healthy', 100.0)
ON CONFLICT DO NOTHING;

-- =================================================================
-- UTILITY FUNCTIONS
-- =================================================================

-- Function to get agent workload
CREATE OR REPLACE FUNCTION get_agent_workload(agent_name VARCHAR(50))
RETURNS TABLE (
    agent_id VARCHAR(50),
    current_load INTEGER,
    max_capacity INTEGER,
    utilization DECIMAL(5,2),
    pending_tasks INTEGER,
    in_progress_tasks INTEGER
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        ar.agent_id,
        ar.current_load,
        ar.max_capacity,
        (ar.current_load::DECIMAL / ar.max_capacity * 100) as utilization,
        COUNT(tq.id) FILTER (WHERE tq.status = 'pending') as pending_tasks,
        COUNT(tq.id) FILTER (WHERE tq.status = 'in_progress') as in_progress_tasks
    FROM agent_registry ar
    LEFT JOIN task_queue tq ON ar.agent_id = tq.agent
    WHERE ar.agent_id = agent_name
    GROUP BY ar.agent_id, ar.current_load, ar.max_capacity;
END;
$$ LANGUAGE plpgsql;

-- Function to get system health overview
CREATE OR REPLACE FUNCTION get_system_health_overview()
RETURNS TABLE (
    component VARCHAR(50),
    status VARCHAR(20),
    health_score DECIMAL(3,2),
    last_check TIMESTAMP WITH TIME ZONE,
    error_count INTEGER
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        sh.component,
        sh.status,
        sh.health_score,
        sh.last_check,
        sh.error_count
    FROM system_health sh
    ORDER BY sh.health_score DESC;
END;
$$ LANGUAGE plpgsql;

-- Function to get workflow status
CREATE OR REPLACE FUNCTION get_workflow_status(exec_id VARCHAR(100))
RETURNS TABLE (
    execution_id VARCHAR(100),
    state VARCHAR(20),
    progress DECIMAL(5,2),
    total_tasks INTEGER,
    completed_tasks INTEGER,
    failed_tasks INTEGER,
    duration INTEGER,
    quality_score DECIMAL(3,2)
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        ws.execution_id,
        ws.state,
        ws.progress,
        ws.total_tasks,
        ws.completed_tasks,
        ws.failed_tasks,
        ws.duration,
        ws.quality_score
    FROM workflow_state ws
    WHERE ws.execution_id = exec_id;
END;
$$ LANGUAGE plpgsql;

-- =================================================================
-- CLEANUP PROCEDURES
-- =================================================================

-- Function to cleanup old completed tasks
CREATE OR REPLACE FUNCTION cleanup_old_tasks(days_old INTEGER DEFAULT 30)
RETURNS INTEGER AS $$
DECLARE
    deleted_count INTEGER;
BEGIN
    DELETE FROM task_queue 
    WHERE status IN ('completed', 'failed', 'cancelled') 
    AND created_at < NOW() - INTERVAL '1 day' * days_old;
    
    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    RETURN deleted_count;
END;
$$ LANGUAGE plpgsql;

-- Function to cleanup old communication logs
CREATE OR REPLACE FUNCTION cleanup_old_communications(days_old INTEGER DEFAULT 7)
RETURNS INTEGER AS $$
DECLARE
    deleted_count INTEGER;
BEGIN
    DELETE FROM communication_log 
    WHERE timestamp < NOW() - INTERVAL '1 day' * days_old;
    
    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    RETURN deleted_count;
END;
$$ LANGUAGE plpgsql;

COMMIT; 