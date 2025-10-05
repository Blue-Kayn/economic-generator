// app/javascript/controllers/property_analyzer_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "urlInput", "results",
    "investmentBtn", "subleaseBtn",
    "buyToLeaseControls", "subleaseControls",
    "btlAgencyFeeEnabled", "btlAgencyFeePercent",
    "btlServiceChargeEnabled", "btlServiceChargeRate",
    "btlManagementFeeEnabled", "btlManagementFeePercent",
    "btlChillerFreeEnabled",
    "btlFurnishingEnabled", "btlFurnishingCost",
    "managementFeeEnabled", "managementFeePercent",
    "chillerFreeEnabled"
  ]

  connect() {
    console.log("Property analyzer connected!")
    this.currentMode = 'sublease'
    this.lastData = null
  }

  handleEnter(event) {
    if (event.key === 'Enter') {
      this.analyze()
    }
  }

  async analyze() {
    const url = this.urlInputTarget.value.trim()
    
    if (!url) {
      alert("Please enter a URL")
      return
    }

    this.resultsTarget.innerHTML = "<p>Loading...</p>"

    try {
      const response = await fetch(`/api/analyze/link?url=${encodeURIComponent(url)}`)
      const data = await response.json()
      console.log("Received data:", data)
      this.lastData = data
      
      // Check for hotel apartment error
      if (data.resolver?.facts?.error === 'hotel_apartment') {
        this.resultsTarget.innerHTML = `
          <div class="error-message">
            <strong>${data.resolver.facts.error_message}</strong>
          </div>
        `
        return
      }
      
      this.renderResults()
    } catch (error) {
      console.error("Error:", error)
      this.resultsTarget.innerHTML = `<div class="error-message">Error: ${error.message}</div>`
    }
  }

  selectInvestmentMode() {
    console.log("Switching to investment mode")
    this.currentMode = 'investment'
    this.updateModeUI()
    if (this.lastData) this.renderResults()
  }

  selectSubleaseMode() {
    console.log("Switching to sublease mode")
    this.currentMode = 'sublease'
    this.updateModeUI()
    if (this.lastData) this.renderResults()
  }

  updateModeUI() {
    this.investmentBtnTarget.classList.toggle('active', this.currentMode === 'investment')
    this.subleaseBtnTarget.classList.toggle('active', this.currentMode === 'sublease')
    
    this.buyToLeaseControlsTarget.style.display = this.currentMode === 'investment' ? 'block' : 'none'
    this.subleaseControlsTarget.style.display = this.currentMode === 'sublease' ? 'block' : 'none'
  }

  updateCalculations() {
    if (this.currentMode === 'investment') {
      this.btlAgencyFeePercentTarget.disabled = !this.btlAgencyFeeEnabledTarget.checked
      this.btlServiceChargeRateTarget.disabled = !this.btlServiceChargeEnabledTarget.checked
      this.btlManagementFeePercentTarget.disabled = !this.btlManagementFeeEnabledTarget.checked
      this.btlFurnishingCostTarget.disabled = !this.btlFurnishingEnabledTarget.checked
    } else {
      this.managementFeePercentTarget.disabled = !this.managementFeeEnabledTarget.checked
    }
    
    if (this.lastData) this.renderResults()
  }

  renderResults() {
    if (!this.lastData) return

    const hasEconomicsData = this.lastData.economics?.status === "ok" && this.lastData.economics?.data
    const listingType = this.lastData.resolver?.facts?.listing_type

    // Check for mode/listing type mismatch
    if (this.currentMode === 'sublease' && listingType === 'sale') {
      this.resultsTarget.innerHTML = `
        <div class="error-message">
          <strong>This is a sales listing. Please input a rental listing.</strong>
        </div>
      `
      return
    }

    if (this.currentMode === 'investment' && listingType === 'rent') {
      this.resultsTarget.innerHTML = `
        <div class="error-message">
          <strong>This is a rental listing. Please input a sales listing.</strong>
        </div>
      `
      return
    }

    if (!hasEconomicsData) {
      this.resultsTarget.innerHTML = `
        <div class="error-message">
          <strong>No Economics Data Available</strong><br>
          ${this.lastData.economics?.user_message || "Could not match building to our database"}
        </div>
      `
      return
    }

    let html = ''

    // Property Details
    if (this.lastData.resolver && this.lastData.resolver.building_name) {
      html += this.renderPropertyDetails(this.lastData.resolver)
    }

    // Fallback warning
    if (this.lastData.selection?.fallback_message) {
      html += `
        <div class="warning-message" style="background: #92400e; border-left: 4px solid #f59e0b; padding: 1.25rem;">
          ${this.lastData.selection.fallback_message}
        </div>
      `
    }

    // Economics
    html += this.renderEconomics(this.lastData.economics.data, this.lastData.resolver)

    // Profitability
    if (this.currentMode === 'sublease') {
      html += this.renderSubleaseCalculations(this.lastData.economics.data, this.lastData.resolver)
    } else {
      html += this.renderBuyToLeaseCalculations(this.lastData.economics.data, this.lastData.resolver)
    }

    // Comparables - use economics.listings which has full projection data
    if (this.lastData.economics?.listings?.length > 0) {
      console.log("Listings data:", this.lastData.economics.listings)
      html += this.renderComparables(this.lastData.economics.listings, this.lastData.resolver)
    } else {
      console.log("No listings found. Full data:", this.lastData)
    }

    this.resultsTarget.innerHTML = html
  }

  renderPropertyDetails(resolver) {
    const listingType = resolver.facts?.listing_type || 'unknown'
    
    let html = `
      <div class="section">
        <h3>Property Details</h3>
        <div class="data-grid">
          <div class="data-label">Building</div>
          <div class="data-value">${resolver.building_name || "Not detected"}</div>
          <div class="data-label">Unit Type</div>
          <div class="data-value">${resolver.unit_type || "Not detected"}</div>
          <div class="data-label">Bedrooms</div>
          <div class="data-value">${resolver.facts?.bedrooms ?? "-"}</div>
          <div class="data-label">Bathrooms</div>
          <div class="data-value">${resolver.facts?.bathrooms ?? "-"}</div>
          <div class="data-label">Size</div>
          <div class="data-value">${resolver.facts?.size || "-"}</div>
    `
    
    if (resolver.facts?.purchase_price) {
      html += `
        <div class="data-label">Purchase Price</div>
        <div class="data-value">AED ${resolver.facts.purchase_price.toLocaleString()}</div>
      `
    }
    
    if (resolver.facts?.yearly_rent) {
      html += `
        <div class="data-label">Yearly Rent</div>
        <div class="data-value">AED ${resolver.facts.yearly_rent.toLocaleString()}</div>
      `
    }
    
    html += `
          <div class="data-label">Listing Type</div>
          <div class="data-value">${listingType === 'sale' ? 'For Sale' : listingType === 'rent' ? 'For Rent' : 'Unknown'}</div>
        </div>
      </div>
    `
    
    return html
  }

  renderEconomics(econ, resolver) {
    const unitType = resolver?.unit_type || "units"
    
    return `
      <div class="section">
        <h3>Rental Economics (Median Projection)</h3>
        
        <div class="methodology-info">
          These projections combine real comparable listings with comprehensive market intelligence on how ${unitType} properties perform throughout the year in Palm Jumeirah. For properties with limited booking history, our algorithm intelligently fills gaps using verified seasonal patterns—while preserving each property's unique market positioning.
        </div>
        
        <div class="data-grid">
          <div class="data-label">Projected Annual Revenue</div>
          <div class="data-value highlight">AED ${econ.rev_p50.toLocaleString()}</div>
          <div class="data-label">Projected Yearly Occupancy</div>
          <div class="data-value">${econ.occ_p50.toFixed(1)}%</div>
          <div class="data-label">Projected Average Daily Rate</div>
          <div class="data-value">AED ${econ.adr_p50.toLocaleString()}</div>
          <div class="data-label">Sample Size</div>
          <div class="data-value">
            ${econ.sample_n} comparable listings
            ${econ.truth_count > 0 ? `<span class="badge">${econ.truth_count} with 365-day data</span>` : ''}
          </div>
          <div class="data-label">Data Date</div>
          <div class="data-value">${econ.data_snapshot_date}</div>
        </div>
      </div>
    `
  }

  renderSubleaseCalculations(econ, resolver) {
    const grossRevenue = econ.rev_p50
    const platformFee = Math.round(grossRevenue * 0.15)
    const afterPlatformFee = grossRevenue - platformFee
    
    const managementFeeEnabled = this.managementFeeEnabledTarget.checked
    const managementFeePercent = parseFloat(this.managementFeePercentTarget.value) || 0
    const managementFee = managementFeeEnabled ? Math.round(afterPlatformFee * (managementFeePercent / 100)) : 0
    const afterManagementFee = afterPlatformFee - managementFee
    
    const sizeSqft = resolver.facts?.size_sqft || 0
    const chillerFree = this.chillerFreeEnabledTarget.checked
    const utilitiesRate = chillerFree ? 9 : 18
    const utilities = sizeSqft > 0 ? Math.round(utilitiesRate * sizeSqft) : null
    
    const occupancyRate = econ.occ_p50 / 100
    const nightsOccupied = Math.round(365 * occupancyRate)
    const tourismDirham = Math.round(12.5 * nightsOccupied)
    
    const yearlyRent = resolver.facts?.yearly_rent || null
    
    let netProfit = afterManagementFee - (utilities || 0) - tourismDirham - (yearlyRent || 0)
    
    let html = `
      <div class="section">
        <h3>Sublease Profitability Analysis</h3>
        
        <div class="breakdown-row">
          <div class="breakdown-label">Gross Airbnb Revenue</div>
          <div class="breakdown-value">AED ${grossRevenue.toLocaleString()}</div>
        </div>
        
        <div class="breakdown-row">
          <div class="breakdown-label">- Platform Fee (15%)</div>
          <div class="breakdown-value negative">- AED ${platformFee.toLocaleString()}</div>
        </div>
    `

    if (managementFeeEnabled && managementFee > 0) {
      html += `
        <div class="breakdown-row">
          <div class="breakdown-label">- Management Fee (${managementFeePercent}%)</div>
          <div class="breakdown-value negative">- AED ${managementFee.toLocaleString()}</div>
        </div>
      `
    }

    if (utilities) {
      html += `
        <div class="breakdown-row">
          <div class="breakdown-label">- Utilities <span class="note">(${utilitiesRate} AED/sqft${chillerFree ? ' - chiller free' : ''})</span></div>
          <div class="breakdown-value negative">- AED ${utilities.toLocaleString()}</div>
        </div>
      `
    }

    html += `
      <div class="breakdown-row">
        <div class="breakdown-label">- Tourism Dirham <span class="note">(12.5 AED × ${nightsOccupied} nights)</span></div>
        <div class="breakdown-value negative">- AED ${tourismDirham.toLocaleString()}</div>
      </div>
    `

    if (yearlyRent) {
      html += `
        <div class="breakdown-row">
          <div class="breakdown-label">- Yearly Rent</div>
          <div class="breakdown-value negative">- AED ${yearlyRent.toLocaleString()}</div>
        </div>
      `
    }

    const profitLabel = netProfit >= 0 ? 'Net Annual Profit' : 'Net Annual Loss'

    html += `
      <div class="breakdown-row total">
        <div class="breakdown-label">${profitLabel}</div>
        <div class="breakdown-value" style="font-size: 1.4rem; font-weight: 700; color: ${netProfit >= 0 ? '#34d399' : '#f87171'} !important;">
          AED ${netProfit.toLocaleString()}
        </div>
      </div>
    </div>
    `

    return html
  }

  renderBuyToLeaseCalculations(econ, resolver) {
    const purchasePrice = resolver.facts?.purchase_price
    
    if (!purchasePrice) {
      return `
        <div class="warning-message">
          ⚠️ Purchase price not detected - this appears to be a rental listing. Switch to "Sublease Profitability" mode.
        </div>
      `
    }
    
    const grossRevenue = econ.rev_p50
    const platformFee = Math.round(grossRevenue * 0.15)
    const afterPlatformFee = grossRevenue - platformFee
    
    const agencyFeeEnabled = this.btlAgencyFeeEnabledTarget.checked
    const agencyFeePercent = parseFloat(this.btlAgencyFeePercentTarget.value) || 0
    const agencyFee = agencyFeeEnabled ? Math.round(purchasePrice * (agencyFeePercent / 100)) : 0
    
    const furnishingEnabled = this.btlFurnishingEnabledTarget.checked
    const furnishingCost = furnishingEnabled ? (parseFloat(this.btlFurnishingCostTarget.value) || 0) : 0
    
    const serviceChargeEnabled = this.btlServiceChargeEnabledTarget.checked
    const serviceChargeRate = parseFloat(this.btlServiceChargeRateTarget.value) || 0
    const sizeSqft = resolver.facts?.size_sqft || 0
    const serviceCharge = serviceChargeEnabled && sizeSqft > 0 ? Math.round(serviceChargeRate * sizeSqft) : 0
    
    const managementFeeEnabled = this.btlManagementFeeEnabledTarget.checked
    const managementFeePercent = parseFloat(this.btlManagementFeePercentTarget.value) || 0
    const managementFee = managementFeeEnabled ? Math.round(afterPlatformFee * (managementFeePercent / 100)) : 0
    const afterManagementFee = afterPlatformFee - managementFee
    
    const chillerFree = this.btlChillerFreeEnabledTarget.checked
    const utilitiesRate = chillerFree ? 9 : 18
    const utilities = sizeSqft > 0 ? Math.round(utilitiesRate * sizeSqft) : 0
    
    const occupancyRate = econ.occ_p50 / 100
    const nightsOccupied = Math.round(365 * occupancyRate)
    const tourismDirham = Math.round(12.5 * nightsOccupied)
    
    const annualNOI = afterManagementFee - utilities - tourismDirham - serviceCharge
    const totalInvestment = purchasePrice + agencyFee + furnishingCost
    const roi = totalInvestment > 0 ? ((annualNOI / totalInvestment) * 100).toFixed(2) : 0
    
    let html = `
      <div class="section">
        <h3>Buy to Lease Profitability Analysis</h3>
        
        <div class="breakdown-row">
          <div class="breakdown-label">Purchase Price</div>
          <div class="breakdown-value">AED ${purchasePrice.toLocaleString()}</div>
        </div>
    `
    
    if (agencyFeeEnabled && agencyFee > 0) {
      html += `
        <div class="breakdown-row">
          <div class="breakdown-label">+ Agency Fee (${agencyFeePercent}%) <span class="note">one-time</span></div>
          <div class="breakdown-value negative">AED ${agencyFee.toLocaleString()}</div>
        </div>
      `
    }

    if (furnishingEnabled && furnishingCost > 0) {
      html += `
        <div class="breakdown-row">
          <div class="breakdown-label">+ Furnishing Cost <span class="note">one-time</span></div>
          <div class="breakdown-value negative">AED ${furnishingCost.toLocaleString()}</div>
        </div>
      `
    }

    if (agencyFeeEnabled || furnishingEnabled) {
      html += `
        <div class="breakdown-row" style="border-top: 1px solid #374151; padding-top: 0.75rem; margin-top: 0.5rem;">
          <div class="breakdown-label" style="font-weight: 600;">Total Investment</div>
          <div class="breakdown-value" style="font-weight: 600;">AED ${totalInvestment.toLocaleString()}</div>
        </div>
      `
    }
    
    html += `
        <div style="height: 1.5rem;"></div>
        
        <div class="breakdown-row">
          <div class="breakdown-label">Gross Airbnb Revenue <span class="note">annual</span></div>
          <div class="breakdown-value positive">AED ${grossRevenue.toLocaleString()}</div>
        </div>
        
        <div class="breakdown-row">
          <div class="breakdown-label">- Platform Fee (15%)</div>
          <div class="breakdown-value negative">- AED ${platformFee.toLocaleString()}</div>
        </div>
    `

    if (managementFeeEnabled && managementFee > 0) {
      html += `
        <div class="breakdown-row">
          <div class="breakdown-label">- Management Fee (${managementFeePercent}%)</div>
          <div class="breakdown-value negative">- AED ${managementFee.toLocaleString()}</div>
        </div>
      `
    }

    if (serviceChargeEnabled && serviceCharge > 0) {
      html += `
        <div class="breakdown-row">
          <div class="breakdown-label">- Service Charge <span class="note">(${serviceChargeRate} AED/sqft)</span></div>
          <div class="breakdown-value negative">- AED ${serviceCharge.toLocaleString()}</div>
        </div>
      `
    }

    if (utilities > 0) {
      html += `
        <div class="breakdown-row">
          <div class="breakdown-label">- Utilities <span class="note">(${utilitiesRate} AED/sqft${chillerFree ? ' - chiller free' : ''})</span></div>
          <div class="breakdown-value negative">- AED ${utilities.toLocaleString()}</div>
        </div>
      `
    }

    html += `
      <div class="breakdown-row">
        <div class="breakdown-label">- Tourism Dirham <span class="note">(12.5 AED × ${nightsOccupied} nights)</span></div>
        <div class="breakdown-value negative">- AED ${tourismDirham.toLocaleString()}</div>
      </div>
      
      <div class="breakdown-row total">
        <div class="breakdown-label">Annual Net Operating Income</div>
        <div class="breakdown-value" style="font-size: 1.2rem; font-weight: 700; color: ${annualNOI >= 0 ? '#34d399' : '#f87171'} !important;">
          AED ${annualNOI.toLocaleString()}
        </div>
      </div>
      
      <div style="height: 1rem;"></div>
      
      <div class="breakdown-row total" style="background: #1f2937; padding: 1rem; border-radius: 8px;">
        <div class="breakdown-label" style="font-size: 1.1rem;">Annual ROI</div>
        <div class="breakdown-value" style="font-size: 1.4rem; font-weight: 700; color: ${roi >= 0 ? '#34d399' : '#f87171'} !important;">
          ${roi}%
        </div>
      </div>
    </div>
    
    <div class="section">
      <h3>Assumptions & Notes</h3>
      <p style="color: #9ca3af; font-size: 0.9rem; line-height: 1.6;">
        • Platform fees (15%) include Airbnb/booking.com commissions<br>
        ${agencyFeeEnabled ? `• Agency fee (${agencyFeePercent}%) is a one-time cost added to initial investment<br>` : ''}
        ${furnishingEnabled ? `• Furnishing cost (AED ${furnishingCost.toLocaleString()}) is a one-time cost added to initial investment<br>` : ''}
        ${serviceChargeEnabled ? `• Service charge (${serviceChargeRate} AED/sqft) is an annual building maintenance fee<br>` : ''}
        ${managementFeeEnabled ? `• Management fee (${managementFeePercent}%) applied to revenue after platform fees<br>` : ''}
        • Utilities calculated at ${utilitiesRate} AED/sqft annually${chillerFree ? ' (chiller-free)' : ''}<br>
        • Tourism Dirham is 12.5 AED per night occupied<br>
        • ROI calculated as: (Annual NOI / Total Investment) × 100<br>
        • Does not include: property appreciation, mortgage interest, maintenance${!managementFeeEnabled ? ', management fees' : ''}${!furnishingEnabled ? ', furnishing costs' : ''}<br>
        • Based on median (p50) projections from ${econ.sample_n} comparable listings<br>
        • <strong>This is a cash purchase analysis - mortgage financing would change ROI calculations</strong>
      </p>
    </div>
    `
    
    return html
  }

  renderComparables(listings, resolver) {
    const buildingName = resolver?.building_name || "this building"
    
    let html = `
      <div class="section">
        <h3>Comparable Listings Used</h3>
        
        <div class="methodology-info">
          The listings below represent actual short-term rentals in ${buildingName} with similar characteristics to the analyzed property. Each comparable has been weighted based on data completeness, with full-year listings (365 days) given priority. Projected values show our tier-aware estimates for full-year performance.
        </div>
        
        <table>
          <thead>
            <tr>
              <th>Airbnb ID</th>
              <th>Days Available</th>
              <th>Actual Revenue</th>
              <th>Actual Occupancy</th>
              <th>Actual ADR</th>
              <th>Projected Revenue (365d)</th>
              <th>Projected Occupancy (365d)</th>
              <th>Projected ADR (365d)</th>
              <th>Link</th>
            </tr>
          </thead>
          <tbody>
    `
    
    listings.forEach(item => {
      // Handle occupancy - can be either decimal (0.97) or percentage (97)
      let actualOcc = "-"
      if (item.raw_occ) {
        actualOcc = item.raw_occ < 1 ? (item.raw_occ * 100).toFixed(1) : item.raw_occ.toFixed(1)
      }
      
      let projectedOcc = "-"
      if (item.projected_occ_365) {
        projectedOcc = item.projected_occ_365 < 1 ? (item.projected_occ_365 * 100).toFixed(1) : item.projected_occ_365.toFixed(1)
      }
      
      html += `
        <tr>
          <td>${item.airbnb_id}</td>
          <td>${item.days_available || "-"}</td>
          <td>AED ${item.raw_revenue ? item.raw_revenue.toLocaleString() : "-"}</td>
          <td>${actualOcc}${actualOcc !== "-" ? "%" : ""}</td>
          <td>AED ${item.raw_adr ? Math.round(item.raw_adr).toLocaleString() : "-"}</td>
          <td>AED ${item.projected_rev_365 ? Math.round(item.projected_rev_365).toLocaleString() : "-"}</td>
          <td>${projectedOcc}${projectedOcc !== "-" ? "%" : ""}</td>
          <td>AED ${item.projected_adr_365 ? Math.round(item.projected_adr_365).toLocaleString() : "-"}</td>
          <td><a href="${item.airbnb_url}" target="_blank">View</a></td>
        </tr>
      `
    })
    
    html += `
          </tbody>
        </table>
      </div>
    `
    
    return html
  }
}