# Vessel Registration, Insurance, and Commercial Access

> Canon status: Draft  
> Mechanics source of truth: `data/world/compliance_rules.json`

## Design principle

Far Haul does not use a single interstellar government. Every inhabited system has its own government or recognized governing authority. Concord standards make commerce interoperable, but they do not replace local sovereignty.

A ship normally has one home registration issued by a system government. Other systems recognize that registration unless it is expired, suspended, fraudulent, or specifically rejected by local law.

Registration and insurance are separate.

Registration establishes the vessel's legal identity, ownership, transponder identity, and certified physical configuration. Insurance transfers defined financial risks. A ship can be registered and uninsured, insured with restrictions, or—where local facilities permit it—unregistered.

## Registration

Registration costs money. Fees vary by hull class, configuration, and inspection burden.

A current registration records the configuration against which the vessel was inspected. Like-for-like maintenance does not normally require a new registration. Major changes can.

Major changes include:
- changing the main engine model or thrust geometry;
- materially changing reactor output;
- altering the primary structural frame;
- changing certified cargo mass or volume;
- adding passenger habitation;
- converting the ship for regulated hazardous cargo;
- changing atmospheric or landing capability.

After such work, the vessel enters a modification-pending state until the required inspection and renewal are completed.

A captain is not physically prevented from departing in that state. Whether the yard permits departure and whether the next port admits the vessel are separate questions.

## Shipyards

Major reputable yards are integrated with their local registry. Major configuration work is documented and commonly reported automatically.

Independent yards occupy the middle ground. They may perform a legitimate modification and give the captain everything needed to renew registration without requiring renewal before departure.

Frontier and gray-market facilities may repair or modify a ship without asking for registration. This is useful, but it can leave the captain with an undocumented or uncertified configuration that becomes a problem when returning to tightly regulated commerce.

Examples:
- Sol, Keshar, Ilos, Concord and Iron Gate major yards require registration for major work.
- Roosevelt Independent Yards can work before renewal and provide documentation.
- Carver Field Dock, Waystation Service Slip and Lastlight Orbital Service can accept unregistered ships.
- Port Meridian contains both regulated commercial slips and less formal independent subcontractors.

## Port access

Port rules are explicit in `data/world/compliance_rules.json`; game code should not infer them from narrative descriptions.

Core commercial ports such as Earth Orbital Freight Terminal and Concord Central Exchange require current recognized registration.

Carver and Tidemark can provide restricted basic access to unregistered vessels.

Talos officially expects registration but enforcement is inconsistent.

Waystation Main Dock does not require registration for basic docking.

Lastlight Orbital can provide basic freight access to an unregistered vessel, but government survey work and controlled biological activity require recognized registration.

Port Meridian Main Freight Ring requires registration. Less formal peripheral facilities elsewhere on the station may accept unregistered vessels.

Being unregistered is therefore not synonymous with being a criminal. It closes doors.

## Insurance

There is no universal insurance mandate.

A captain may operate entirely uninsured if the facilities and contracts involved permit it. The captain then retains the financial risk.

Insurance becomes commercially important because other parties can require a certificate as a condition of doing business. Examples include:
- lenders requiring hull coverage;
- passenger operators requiring liability coverage;
- high-value cargo owners requiring cargo and carrier-liability coverage;
- hazardous facilities requiring liability or environmental coverage;
- government or research contracts specifying minimum coverage.

A basic freight berth can therefore allow an uninsured ship while a specific cargo sitting at that same berth cannot be accepted without insurance.

## Policy restrictions and violations

Policies can restrict operating area, cargo class, crew qualification, vessel configuration, or maintenance status.

These restrictions do not function as invisible barriers. The captain can violate them.

An insurer may discover the violation through connected port records, manifests, registry updates, yard records, inspections, distress/rescue records, audits, or a later claim. Informal frontier activity is much less visible than submitting a restricted hazardous manifest at Concord.

Possible consequences include an audit, higher premiums, new restrictions, nonrenewal, cancellation, or denial of a claim when the violation is materially related to the loss. Intentionally false statements can create a separate fraud issue.

This makes compliance a risk/reward decision rather than a binary permission system.

## Mechanics contract

The game should read port and yard access from `data/world/compliance_rules.json`.

Each port has:
- `registration_requirement`;
- `insurance_requirement`;
- `registration_enforcement`;
- `unregistered_basic_access`;
- `insurance_triggers`.

Each yard has:
- `registration_to_accept_work`;
- `major_change_reporting`;
- `can_leave_with_unrenewed_major_changes`.

Contracts can impose requirements beyond the port's minimum rules. A port that permits uninsured docking does not imply every contract offered there permits an uninsured carrier.

Narrative files explain why these rules exist. Structured data determines what the game does.


## Registration economics

Registration is intended to be a recurring operating decision rather than a negligible menu fee. Initial balance data lives in `data/world/registration_economics.json`.

Smaller commercial ships have lower registration and inspection costs and longer validity periods. Heavy and superheavy ships cost substantially more to certify and renew because inspection burden increases with scale. Individual registries apply local cost and inspection modifiers. New Houston is deliberately attractive to independents; Port Meridian is convenient but expensive; frontier offices can be inexpensive administratively while still charging more for scarce inspection capacity.

Four inspection categories are defined: initial registration, routine renewal, major modification, and post-casualty inspection. Registration violations have explicit fine values and indicate whether the local authority may ground the vessel.

The numbers are balance values and can change without rewriting setting lore.

## Insurance products

Insurance is sold as separate products rather than a single insured/uninsured switch. Initial products include Basic Hull, Comprehensive Hull, Carrier Liability, Cargo Cover, Passenger Liability, Environmental Liability, and a Frontier Endorsement.

Premium calculation can consider insured value, hull class, operating region, claims/compliance history, and configuration risk. Deductibles remain part of the policy, so insurance reduces risk rather than eliminating it.

A financed ship normally needs hull coverage because the lender has money at risk. High-value cargo commonly requires carrier liability and cargo cover. Passenger work normally requires passenger liability. Hazardous cargo can require environmental liability. A frontier expedition can require a frontier endorsement when the base policy excludes the route.

## Contract eligibility

Structured requirements live in `data/world/contract_compliance.json`.

Contract requirements are resolved separately from port requirements. A captain may legally dock at a port while being ineligible for most of its freight board.

Ordinary bulk and speculative frontier work can sometimes be offered to unregistered operators. Reputable commercial, passenger, hazardous, scientific, and government work generally requires current recognized registration. Higher-risk work adds specific insurance products and ship endorsements.

The contract UI should disclose known unmet issuer requirements before acceptance. Insurer exposure is different: a captain may satisfy the cargo issuer while knowingly operating outside some unrelated policy condition.

## Inspections and detection

`data/world/compliance_inspections.json` defines registry checks, customs checks, random safety inspections, incident inspections, and contract-certificate verification.

Enforcement is not omniscient. Strict connected ports perform reliable registry checks and more frequent inspections. Frontier ports inspect less often. Prior violations, recent major modifications, hazardous cargo, and incidents can increase scrutiny.

Possible results include clearance, warning, fines, restricted berths, registration holds, cargo refusal, and insurer notification.

The guiding rule is that detection should follow visible institutions and records. If nobody with access to the information has observed or transmitted a violation, the simulation should not pretend that they have.
