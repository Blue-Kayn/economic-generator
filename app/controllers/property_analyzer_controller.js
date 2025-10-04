// app/javascript/controllers/property_analyzer_controller.js
import { Controller } from "@hotwired/stimulus"
import { ResultsRenderer } from "./property_analyzer/results_renderer"
import { SubleaseCalculator } from "./property_analyzer/sublease_calculator"
import { BuyToLeaseCalculator } from "./property_analyzer/buy_to_lease_calculator"

export default class extends Controller {
  static targets = [
    "urlInput", "results",
    "investmentBtn", "subleaseBtn",
    "buyToLeaseControls", "subleaseControls",
    // BTL controls
    "btlAgencyFeeEnabled", "btlAgencyFeePercent",
    "btlServiceChargeEnabled", "btlServiceChargeRate",
    "btlManagementFeeEnabled", "btlManagementFeePercent",
    "btlChillerFreeEnabled",
    // Sublease controls
    "managementFeeEnabled", "managementFeePercent",
    "chillerFreeEnabled"
  ]

  connect() {
    this.currentMode = 'sublease'
    this.lastData = null
    this.renderer = new ResultsRenderer(this.resultsTarget)
    this.subleaseCalc = new SubleaseCalculator()
    this.btlCalc = new BuyToLeaseCalculator()
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
      this.lastData = data
      this.renderResults()
    } catch (error) {
      this.resultsTarget.innerHTML = `<div class="error-message">Error: ${error.message}</div>`
    }
  }

  selectInvestmentMode() {
    this.currentMode = 'investment'
    this.updateModeUI()
    this.renderResults()
  }

  selectSubleaseMode() {
    this.currentMode = 'sublease'
    this.updateModeUI()
    this.renderResults()
  }

  updateModeUI() {
    // Update button states
    this.investmentBtnTarget.classList.toggle('active', this.currentMode === 'investment')
    this.subleaseBtnTarget.classList.toggle('active', this.currentMode === 'sublease')
    
    // Show/hide controls
    this.buyToLeaseControlsTarget.style.display = this.currentMode === 'investment' ? 'block' : 'none'
    this.subleaseControlsTarget.style.display = this.currentMode === 'sublease' ? 'block' : 'none'
  }

  updateCalculations() {
    // Enable/disable inputs based on checkboxes
    if (this.currentMode === 'investment') {
      this.btlAgencyFeePercentTarget.disabled = !this.btlAgencyFeeEnabledTarget.checked
      this.btlServiceChargeRateTarget.disabled = !this.btlServiceChargeEnabledTarget.checked
      this.btlManagementFeePercentTarget.disabled = !this.btlManagementFeeEnabledTarget.checked
    } else {
      this.managementFeePercentTarget.disabled = !this.managementFeeEnabledTarget.checked
    }
    
    this.renderResults()
  }

  renderResults() {
    if (!this.lastData) return

    const hasEconomicsData = this.lastData.economics?.status === "ok" && this.lastData.economics?.data

    if (!hasEconomicsData) {
      this.renderer.renderError(this.lastData.economics?.user_message || "No data available")
      return
    }

    // Render property details
    this.renderer.renderPropertyDetails(this.lastData.resolver)
    
    // Render fallback warning if exists
    if (this.lastData.selection?.fallback_message) {
      this.renderer.renderWarning(this.lastData.selection.fallback_message)
    }

    // Render economics
    this.renderer.renderEconomics(this.lastData.economics.data, this.lastData.resolver)

    // Render profitability based on mode
    if (this.currentMode === 'sublease') {
      const config = this.getSubleaseConfig()
      this.subleaseCalc.render(
        this.resultsTarget,
        this.lastData.economics.data,
        this.lastData.resolver,
        config
      )
    } else {
      const config = this.getBuyToLeaseConfig()
      this.btlCalc.render(
        this.resultsTarget,
        this.lastData.economics.data,
        this.lastData.resolver,
        config
      )
    }

    // Render comparable listings
    if (this.lastData.economics.listings?.length > 0) {
      this.renderer.renderComparables(
        this.lastData.economics.listings,
        this.lastData.resolver
      )
    }
  }

  getSubleaseConfig() {
    return {
      managementFeeEnabled: this.managementFeeEnabledTarget.checked,
      managementFeePercent: parseFloat(this.managementFeePercentTarget.value) || 0,
      chillerFree: this.chillerFreeEnabledTarget.checked
    }
  }

  getBuyToLeaseConfig() {
    return {
      agencyFeeEnabled: this.btlAgencyFeeEnabledTarget.checked,
      agencyFeePercent: parseFloat(this.btlAgencyFeePercentTarget.value) || 0,
      serviceChargeEnabled: this.btlServiceChargeEnabledTarget.checked,
      serviceChargeRate: parseFloat(this.btlServiceChargeRateTarget.value) || 0,
      managementFeeEnabled: this.btlManagementFeeEnabledTarget.checked,
      managementFeePercent: parseFloat(this.btlManagementFeePercentTarget.value) || 0,
      chillerFree: this.btlChillerFreeEnabledTarget.checked
    }
  }
}