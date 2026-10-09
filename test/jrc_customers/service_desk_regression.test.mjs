// Executes the existing official source assertions unchanged, without Vue or Rails.
import test from 'node:test';
import assert from 'node:assert/strict';
import './service_desk_node_harness.mjs';
const { registerContractCases } = await import('../../app/javascript/dashboard/routes/dashboard/serviceDesk/__tests__/contractCases.js');
const { registerCp4Cases } = await import('../../app/javascript/dashboard/routes/dashboard/serviceDesk/__tests__/cp4Cases.js');
const { registerCp5Cases } = await import('../../app/javascript/dashboard/routes/dashboard/serviceDesk/__tests__/cp5Cases.js');
const { registerLifecycleCases } = await import('../../app/javascript/dashboard/routes/dashboard/serviceDesk/__tests__/lifecycleCases.js');
const { registerConfigurationCases } = await import('../../app/javascript/dashboard/routes/dashboard/serviceDesk/__tests__/configurationCases.js');
const { registerStructureCases } = await import('../../app/javascript/dashboard/routes/dashboard/serviceDesk/__tests__/structureCases.js');
for (const register of [registerContractCases, registerCp4Cases, registerCp5Cases, registerLifecycleCases, registerConfigurationCases, registerStructureCases]) register(test, assert);
