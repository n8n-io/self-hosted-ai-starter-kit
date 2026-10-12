/*
Require all workflows to include a list of predefined nodes. 
Check on workflow activation and throw error if no required node is active and connected.
*/
const REQUIRED_NODES = [
	{
		type: 'n8n-nodes-base.n8nTrainingCustomerDatastore',
		name: 'Customer Datastore (n8n training)',
	},
	{
		type: 'n8n-nodes-base.n8nTrainingCustomerMessenger',
		name: 'Customer Messenger (n8n training)',
	},
];

function throwRequiredNodesError() {
	const nodesMSG = REQUIRED_NODES.map((n) => n.name).join('\n');
	throw new Error(`You need to use one of these node: ${nodesMSG}`);
}

function checkRequiredNodes(workflowData) {
	// ignore empty workflow
	if (!workflowData.nodes.length) {
		return;
	}

	// get all required enabled nodes
	const nodes = workflowData.nodes.filter(
		(n) => !n.disabled && REQUIRED_NODES.some((nn) => nn.type === n.type),
	);
	if (!nodes.length) throwRequiredNodesError();

	// get all connections from or to a required node
	const connections = Object.entries(workflowData.connections).filter(([key, value]) => {
		const json = JSON.stringify(value);
		// ignore empty connections
		if (!json.includes('node')) return false;
		// filter connections including at least one of required nodes
		if (nodes.some((n) => n.name === key)) return true;
		if (nodes.some((n) => json.includes(`"${n.name}"`))) return true;
		return false;
	});
	if (!connections.length) throwRequiredNodesError();
}

module.exports = {
	workflow: {
		activate: [
			async function (workflowData) {
				checkRequiredNodes(workflowData);
			},
		],
	},
};
