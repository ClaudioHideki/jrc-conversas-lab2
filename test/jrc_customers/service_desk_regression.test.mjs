// Executes the existing official source assertions unchanged, without Vue or Rails.
import test from 'node:test';
import assert from 'node:assert/strict';
import { registerContractCases } from '../../app/javascript/dashboard/routes/dashboard/serviceDesk/__tests__/contractCases.js';
import { registerCp4Cases } from '../../app/javascript/dashboard/routes/dashboard/serviceDesk/__tests__/cp4Cases.js';
import { registerCp5Cases } from '../../app/javascript/dashboard/routes/dashboard/serviceDesk/__tests__/cp5Cases.js';
import { registerLifecycleCases } from '../../app/javascript/dashboard/routes/dashboard/serviceDesk/__tests__/lifecycleCases.js';
import { registerConfigurationCases } from '../../app/javascript/dashboard/routes/dashboard/serviceDesk/__tests__/configurationCases.js';
import { registerStructureCases } from '../../app/javascript/dashboard/routes/dashboard/serviceDesk/__tests__/structureCases.js';
for (const register of [registerContractCases, registerCp4Cases, registerCp5Cases, registerLifecycleCases, registerConfigurationCases, registerStructureCases]) register(test, assert);
